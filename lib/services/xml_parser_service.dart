import 'dart:io';
import 'package:xml/xml.dart';
import '../models/unipaas_models.dart';
import 'schema_service.dart';

/// Generation marker uniPaaS uses in `{generation,field}` references to mean
/// "a variable of the Main Program" rather than an ancestor task.
const String kGlobalGeneration = '32768';

/// Matches a reference to a Main Program variable, e.g. `{32768,2}`.
final RegExp _globalRefPattern = RegExp('\\{$kGlobalGeneration\\s*,\\s*(\\d+)\\}');

/// A `Locate` or `Range` attached to a dataview field. MIN and MAX hold
/// *expression ids*, not values.
class _FilterSpec {
  final String kind; // 'Locate' or 'Range'
  final String minExpId;
  final String maxExpId;

  _FilterSpec(this.kind, this.minExpId, this.maxExpId);
}

/// One `Select` line of the dataview, captured with the table context that was
/// active where it appeared.
class _SelectRecord {
  final String fieldId; // Select/@FieldID — what {generation,N} references
  final String typeVal; // 'R' real column, 'V' virtual/parameter
  final String colVal; // column ISN when real, ordinal position when virtual
  final bool isParameterFlag;
  final String tableObj; // empty for virtuals
  final String tableAlias; // alias of the table instance in scope
  final int joinIndex; // -1 when the field belongs to the main source
  final String assExpId; // <ASS val> — the field's init/assignment expression
  final String realVarName; // <REAL_VNAME_TXT val> — user-renamed alias
  final bool partOfDataview;
  final List<_FilterSpec> filters;

  _SelectRecord({
    required this.fieldId,
    required this.typeVal,
    required this.colVal,
    required this.isParameterFlag,
    required this.tableObj,
    required this.tableAlias,
    required this.joinIndex,
    required this.assExpId,
    required this.realVarName,
    required this.partOfDataview,
    required this.filters,
  });

  bool get isRealColumn => typeVal == 'R';
}

class _LinkContext {
  final String tableObj;
  final String tableAlias;
  final int joinIndex;
  _LinkContext(this.tableObj, this.tableAlias, this.joinIndex);
}

/// A field of an ancestor task as seen from a descendant. A child task runs
/// once per parent record, so the parent's columns arrive as values rather than
/// as tables the child query can join to.
class _AncestorField {
  final String ref;
  final String sqlType;
  _AncestorField(this.ref, this.sqlType);
}

class XmlParserService {
  final SchemaService schemaService;
  final Map<String, GlobalVarInfo> _mainProgramGlobals = {};

  XmlParserService(this.schemaService);

  Map<String, GlobalVarInfo> get mainProgramGlobals => _mainProgramGlobals;
  void parseMainProgramGlobals(String xmlString) => _parseMainProgramGlobals(xmlString);

  Future<ParsedProgram?> parseProgramFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    final sourceDir = file.parent.path;
    await ensureMainProgramLoaded(sourceDir);

    final xmlString = await file.readAsString();
    return parseProgramString(xmlString, filePath);
  }

  Future<void> ensureMainProgramLoaded(String sourceDir) async {
    if (_mainProgramGlobals.isNotEmpty) return;

    final dir = Directory(sourceDir);
    if (await dir.exists()) {
      try {
        final entities = await dir.list().toList();
        for (final entity in entities) {
          if (entity is File) {
            final filename = entity.path.split(Platform.pathSeparator).last.toLowerCase();
            if (filename == 'prg_1.xml' || filename == 'prg_0001.xml' || filename == 'mainprogram.xml') {
              final xmlString = await entity.readAsString();
              _parseMainProgramGlobals(xmlString);
              if (_mainProgramGlobals.isNotEmpty) return;
            }
          }
        }
      } catch (_) {}
    }

    final candidates = [
      '$sourceDir/Prg_1.xml',
      '$sourceDir/source/Prg_1.xml',
      '${dir.parent.path}/Prg_1.xml',
      '${dir.parent.path}/source/Prg_1.xml',
    ];

    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) {
        try {
          final xmlString = await file.readAsString();
          _parseMainProgramGlobals(xmlString);
          if (_mainProgramGlobals.isNotEmpty) break;
        } catch (_) {}
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Column typing
  // ---------------------------------------------------------------------------

  String _extractColumnSqlType(XmlElement colNode) {
    final propList = colNode.findElements('PropertyList').firstOrNull;
    if (propList == null) return 'NVARCHAR(255)';

    return UnipaasTypeMapper.sqlType(
      attrObj: propList.findElements('Model').firstOrNull?.getAttribute('attr_obj') ?? '',
      picture: propList.findElements('Picture').firstOrNull?.getAttribute('valUnicode') ?? '',
      whole: int.tryParse(propList.findElements('_Whole').firstOrNull?.getAttribute('val') ?? '') ?? 0,
      dec: int.tryParse(propList.findElements('_Dec').firstOrNull?.getAttribute('val') ?? '') ?? 0,
      size: int.tryParse(propList.findElements('Size').firstOrNull?.getAttribute('val') ?? '') ?? 0,
    );
  }

  // ---------------------------------------------------------------------------
  // Main Program globals
  // ---------------------------------------------------------------------------

  void _parseMainProgramGlobals(String xmlString) {
    try {
      final doc = XmlDocument.parse(xmlString);
      final mainTask = doc.findAllElements('Task').where((e) {
        return e.getAttribute('MainProgram') == 'Y' ||
            e.findElements('Header').firstOrNull?.getAttribute('Description') == 'Main Program';
      }).firstOrNull ?? doc.findAllElements('Task').firstOrNull;

      if (mainTask == null) return;

      // Variables of the Main Program, in declaration order.
      final byIsn = <String, GlobalVarInfo>{};
      final byPosition = <String, GlobalVarInfo>{};
      final colNodes = mainTask.findElements('Resource').firstOrNull?.findAllElements('Column');
      if (colNodes != null) {
        int position = 1;
        for (final col in colNodes) {
          final colIsn = col.getAttribute('id') ?? '';
          final rawName = col.getAttribute('name') ?? '';
          if (rawName.isNotEmpty) {
            final info = GlobalVarInfo(
              fieldId: colIsn,
              name: _sanitiseName(rawName),
              sqlType: _extractColumnSqlType(col),
            );
            byPosition[position.toString()] = info;
            if (colIsn.isNotEmpty) byIsn[colIsn] = info;
          }
          position++;
        }
      }

      // {32768,N} addresses a Main Program field by its Select FieldID, so map
      // each FieldID to the variable that Select reads.
      final logicUnits = mainTask.findElements('TaskLogic').firstOrNull?.findElements('LogicUnit') ?? <XmlElement>[];
      for (final lu in logicUnits) {
        final logicLines = lu.findElements('LogicLines').firstOrNull?.findElements('LogicLine');
        if (logicLines == null) continue;
        for (final line in logicLines) {
          final selectNode = line.findElements('Select').firstOrNull;
          if (selectNode == null) continue;
          final fieldId = selectNode.getAttribute('FieldID') ?? '';
          final colVal = selectNode.findElements('Column').firstOrNull?.getAttribute('val') ?? '';
          // Virtual selects address the variable list positionally; fall back
          // to the ISN when the position is out of range.
          final info = byPosition[colVal] ?? byIsn[colVal];
          if (fieldId.isNotEmpty && info != null) {
            _mainProgramGlobals[fieldId] = info;
          }
        }
      }

      byPosition.forEach((position, info) {
        _mainProgramGlobals.putIfAbsent(position, () => info);
      });
    } catch (e) {
      // ignore: avoid_print
      print('Error parsing MainProgram globals: $e');
    }
  }

  static String _sanitiseName(String raw) => raw.trim().replaceAll(RegExp(r'[\s?]+'), '_');

  // ---------------------------------------------------------------------------
  // Program
  // ---------------------------------------------------------------------------

  ParsedProgram? parseProgramString(String xmlString, String filename) {
    try {
      if (filename.contains('Prg_1.xml') || xmlString.contains('MainProgram="Y"')) {
        _parseMainProgramGlobals(xmlString);
      }
      final doc = XmlDocument.parse(xmlString);
      final topTasks = <ParsedTask>[];
      final extractedParameters = <ProgramParameter>[];

      String progId = '';
      String progName = filename;

      final idMatch = RegExp(r'Prg_(\d+)\.xml').firstMatch(filename);
      if (idMatch != null) {
        progId = idMatch.group(1)!;
      }

      final programsNode = doc.findAllElements('Programs').firstOrNull;
      final rootTaskNodes = (programsNode != null)
          ? programsNode.children.whereType<XmlElement>().where((e) => e.name.local == 'Task')
          : doc.children.whereType<XmlElement>().where((e) => e.name.local == 'Task');

      for (final rootTaskNode in rootTaskNodes) {
        final parsedTask = _parseSingleTask(
          rootTaskNode,
          parentTaskId: null,
          level: 0,
          extractedParameters: extractedParameters,
          generationChain: const [],
          ancestorTypes: const {},
        );
        if (parsedTask != null) {
          if (progId.isEmpty && parsedTask.taskId.isNotEmpty) progId = parsedTask.taskId;
          if (progName == filename && parsedTask.description.isNotEmpty) progName = parsedTask.description;
          topTasks.add(parsedTask);
        }
      }

      return ParsedProgram(
        id: progId,
        filename: filename,
        name: progName,
        tasks: topTasks,
        extractedParameters: extractedParameters,
        mainProgramGlobals: Map.from(_mainProgramGlobals),
      );
    } catch (e) {
      // ignore: avoid_print
      print('Error parsing XML string: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Task
  // ---------------------------------------------------------------------------

  /// [generationChain] holds the resolved field references of the ancestor
  /// tasks: index 0 is the parent (`{1,N}`), index 1 the grandparent (`{2,N}`)
  /// and so on.
  ParsedTask? _parseSingleTask(
    XmlElement taskNode, {
    String? parentTaskId,
    int level = 0,
    required List<ProgramParameter> extractedParameters,
    required List<Map<String, _AncestorField>> generationChain,
    required Map<String, String> ancestorTypes,
  }) {
    final headerNode = taskNode.findElements('Header').firstOrNull;
    String taskId = '';
    String taskIsn = '1';
    String taskDesc = level == 0 ? 'Main Task' : 'Sub-Task';

    if (headerNode != null) {
      taskId = headerNode.getAttribute('id') ?? '';
      taskIsn = headerNode.getAttribute('ISN_2') ?? '1';
      final rawDesc = headerNode.getAttribute('Description');
      if (rawDesc != null && rawDesc.isNotEmpty) {
        taskDesc = rawDesc;
      } else if (taskId.isNotEmpty) {
        taskDesc = 'Task $taskId';
      }
    }

    final informationNode = taskNode.findElements('Information').firstOrNull;

    // Main source. `<DB comp="-1" obj="83"/>` carries the object on the DB
    // element itself; `<DB comp="-1"/>` means the task has no main source.
    final mainTableObj = _tableKeyOf(informationNode?.findElements('DB').firstOrNull);
    final mainTableName = schemaService.getTableName(mainTableObj);

    // Locate/Range/ASS address expressions by their 1-based position in the
    // Expressions block, NOT by the `id` attribute. The ids are shuffled in
    // most programs; verified against column types across the corpus, position
    // agrees 99.6% of the time and the id reading only 59%.
    final expMap = <String, String>{};
    final expAttrMap = <String, String>{};
    final expNodes = taskNode.findElements('Expressions').firstOrNull?.findElements('Expression');
    if (expNodes != null) {
      int position = 1;
      for (final exp in expNodes) {
        final syntax = exp.findElements('ExpSyntax').firstOrNull?.getAttribute('val');
        if (syntax != null) {
          expMap[position.toString()] = syntax;
          expAttrMap[position.toString()] =
              exp.findElements('ExpAttribute').firstOrNull?.getAttribute('val') ?? '';

          // Surface every Main Program global the task mentions, including
          // ones used only by conditions the generator does not emit, so the
          // parameter list stays complete for the caller.
          for (final m in _globalRefPattern.allMatches(syntax)) {
            final global = _mainProgramGlobals[m.group(1)!];
            if (global == null) continue;
            if (extractedParameters.any((p) => p.name == global.name)) continue;
            extractedParameters.add(ProgramParameter(
              fieldId: m.group(1)!,
              colId: '',
              name: global.name,
              type: global.sqlType,
              isParameter: true,
            ));
          }
        }
        position++;
      }
    }

    // Task-local variables (virtuals and parameters), in declaration order.
    final varByPosition = <String, String>{};
    final varByIsn = <String, String>{};
    final varTypeByPosition = <String, String>{};
    final varTypeByIsn = <String, String>{};
    final colNodes = taskNode.findElements('Resource').firstOrNull?.findAllElements('Column');
    if (colNodes != null) {
      int position = 1;
      for (final col in colNodes) {
        final colIsn = col.getAttribute('id') ?? '';
        final name = _sanitiseName(col.getAttribute('name') ?? 'Var_$position');
        final sqlType = _extractColumnSqlType(col);

        varByPosition[position.toString()] = name;
        varTypeByPosition[position.toString()] = sqlType;
        if (colIsn.isNotEmpty) {
          varByIsn[colIsn] = name;
          varTypeByIsn[colIsn] = sqlType;
        }
        position++;
      }
    }

    final joins = <TableJoin>[];
    final aliasCounts = <String, int>{};
    final mainTableAlias = mainTableObj.isEmpty
        ? ''
        : _allocateAlias(mainTableName, aliasCounts);
    final records = _collectDataviewSelects(
      taskNode,
      mainTableObj,
      mainTableAlias,
      joins,
      aliasCounts,
    );

    // --- Resolve every field before evaluating any expression, because an
    // expression may reference a field declared further down the dataview.
    final fieldRefs = <String, String>{}; // FieldID -> SQL reference
    // The same fields as a descendant task sees them.
    final descendantRefs = <String, _AncestorField>{};
    final taskParameters = <ProgramParameter>[];
    final columnByField = <String, SelectedColumn>{};

    for (final record in records) {
      if (record.isRealColumn) {
        if (record.tableObj.isEmpty || record.colVal.isEmpty) continue;
        final colName = schemaService.getColumnName(record.tableObj, record.colVal);
        fieldRefs[record.fieldId] = '[${record.tableAlias}].[$colName]';
        descendantRefs[record.fieldId] = _AncestorField(
          '@${record.tableAlias}_$colName',
          schemaService.getColumnSqlType(record.tableObj, record.colVal),
        );
      } else {
        // Virtual selects address the variable list positionally.
        final name = varByPosition[record.colVal] ??
            varByIsn[record.colVal] ??
            'Var_${record.colVal}';
        final sqlType = varTypeByPosition[record.colVal] ??
            varTypeByIsn[record.colVal] ??
            'NVARCHAR(255)';
        fieldRefs[record.fieldId] = '@$name';
        descendantRefs[record.fieldId] = _AncestorField('@$name', sqlType);

        final looksLikeParameter = record.isParameterFlag || name.startsWith('p_');
        final parameter = ProgramParameter(
          fieldId: record.fieldId,
          colId: record.colVal,
          name: name,
          type: sqlType,
          isParameter: looksLikeParameter,
        );
        if (!extractedParameters.any((p) => p.name == name)) {
          extractedParameters.add(parameter);
        }
        if (looksLikeParameter && !taskParameters.any((p) => p.name == name)) {
          taskParameters.add(parameter);
        }
      }
    }

    String resolve(String expId) {
      final syntax = expMap[expId];
      if (syntax == null) return '';
      return _resolveExpression(syntax, fieldRefs, generationChain);
    }

    // --- Emit selected columns and filters.
    final selectedColumns = <SelectedColumn>[];
    final whereConditions = <WhereCondition>[];

    for (final record in records) {
      if (!record.isRealColumn) continue;
      if (record.tableObj.isEmpty || record.colVal.isEmpty) continue;

      final tableName = schemaService.getTableName(record.tableObj);
      final colName = schemaService.getColumnName(record.tableObj, record.colVal);
      final alias = record.realVarName.isNotEmpty
          ? _sanitiseName(record.realVarName)
          : schemaService.getColumnAlias(
              record.tableObj,
              record.colVal,
              fallback: colName,
            );

      final selected = SelectedColumn(
        fieldId: record.fieldId,
        tableObj: record.tableObj,
        tableName: record.tableAlias,
        tableRealName: tableName,
        colId: record.colVal,
        colName: colName,
        alias: alias,
        // ASS is the field's assignment expression. It is not a filter and
        // must never be confused with Locate/Range.
        initExpression: record.assExpId.isNotEmpty ? resolve(record.assExpId) : '',
      );
      columnByField[record.fieldId] = selected;
      if (record.partOfDataview) {
        selectedColumns.add(selected);
      }

      for (final filter in record.filters) {
        final condition = _buildCondition(
          filter: filter,
          resolve: resolve,
          expMap: expMap,
        );
        if (condition == null) continue;

        _registerImplicitParameters(condition.$1, extractedParameters, ancestorTypes);
        if (condition.$2.isNotEmpty) {
          _registerImplicitParameters(condition.$2, extractedParameters, ancestorTypes);
        }

        if (record.joinIndex >= 0) {
          joins[record.joinIndex].conditions.add(JoinCondition(
                targetColName: colName,
                sourceExpression: condition.$1,
                operator: condition.$3,
                upperExpression: condition.$2,
              ));
        } else {
          whereConditions.add(WhereCondition(
            tableName: record.tableAlias,
            colName: colName,
            operator: condition.$3,
            valueExpression: condition.$1,
            upperExpression: condition.$2,
            origin: filter.kind,
          ));
        }
      }
    }

    // --- Values written by the task's Update operations.
    final assignments = <ColumnAssignment>[];
    for (final update in _updateOperations(taskNode)) {
      // An Update carrying <Parent> targets an ancestor task's field, which is
      // not part of this task's own statement.
      if (update.findElements('Parent').isNotEmpty) continue;

      final fieldId = update.findElements('FieldID').firstOrNull?.getAttribute('val') ?? '';
      final withValue = update.findElements('WithValue').firstOrNull?.getAttribute('val') ?? '';
      final column = columnByField[fieldId];
      if (column == null || withValue.isEmpty || !expMap.containsKey(withValue)) continue;

      final expression = resolve(withValue);
      if (expression.isEmpty) continue;
      _registerImplicitParameters(expression, extractedParameters, ancestorTypes);

      assignments.add(ColumnAssignment(
        fieldId: fieldId,
        tableObj: column.tableObj,
        tableAlias: column.tableName,
        tableName: column.tableRealName,
        colName: column.colName,
        expression: expression,
        incremental:
            update.findElements('Incremental').firstOrNull?.getAttribute('val') == 'I',
      ));
    }

    // --- Task-level SQL WHERE, written by hand in the uniPaaS task.
    final sqlWhereClause = _parseSqlWhere(taskNode, fieldRefs, columnByField);

    // --- ORDER BY, from the index the dataview reads through.
    final orderBy = _buildOrderBy(
      taskNode: taskNode,
      informationNode: informationNode,
      mainTableObj: mainTableObj,
      mainTableAlias: mainTableAlias,
      records: records,
      columnByField: columnByField,
    );

    // Ancestor chain seen by this task's children: index 0 is this task, which
    // a child addresses as {1,N}.
    final childChain = <Map<String, _AncestorField>>[descendantRefs, ...generationChain];
    final childTypes = <String, String>{...ancestorTypes};
    for (final field in descendantRefs.values) {
      if (field.ref.startsWith('@')) {
        childTypes[field.ref.substring(1)] = field.sqlType;
      }
    }

    final childTaskNodes = taskNode.children.whereType<XmlElement>().where((e) => e.name.local == 'Task');
    final parsedSubTasks = <ParsedTask>[];
    for (final childNode in childTaskNodes) {
      final childTask = _parseSingleTask(
        childNode,
        parentTaskId: taskId,
        level: level + 1,
        extractedParameters: extractedParameters,
        generationChain: childChain,
        ancestorTypes: childTypes,
      );
      if (childTask != null) parsedSubTasks.add(childTask);
    }

    return ParsedTask(
      taskId: taskId,
      taskIsn: taskIsn,
      parentTaskId: parentTaskId,
      level: level,
      description: taskDesc,
      mainTableObj: mainTableObj,
      mainTableName: mainTableName,
      mainTableAlias: mainTableAlias,
      columns: selectedColumns,
      joins: joins,
      whereConditions: whereConditions,
      parameters: taskParameters,
      subTasks: parsedSubTasks,
      sqlWhereClause: sqlWhereClause,
      assignments: assignments,
      externalTables: {
        if (SchemaService.isExternalTable(mainTableObj)) mainTableName,
        for (final join in joins)
          if (SchemaService.isExternalTable(join.targetTableObj)) join.targetTableName,
      }.toList(),
      initialMode: informationNode?.findElements('InitialMode').firstOrNull?.getAttribute('val') ?? '',
      orderBy: orderBy,
      dataSource: schemaService.getDataSource(mainTableObj),
      mainSourceIsSql: mainTableObj.isEmpty || schemaService.isSqlTable(mainTableObj),
    );
  }

  // ---------------------------------------------------------------------------
  // Dataview walk
  // ---------------------------------------------------------------------------

  /// Walks the task's dataview logic unit, recording every Select together with
  /// the table instance that was in scope, and appending a [TableJoin] per
  /// link. Each instance gets its own alias so that a table linked twice does
  /// not collapse into one.
  List<_SelectRecord> _collectDataviewSelects(
    XmlElement taskNode,
    String mainTableObj,
    String mainTableAlias,
    List<TableJoin> joins,
    Map<String, int> aliasCounts,
  ) {
    final records = <_SelectRecord>[];
    final allUnits = taskNode.findElements('TaskLogic').firstOrNull?.findElements('LogicUnit') ?? <XmlElement>[];

    // Only the dataview unit describes the query. Links that appear in event
    // handlers are runtime lookups, not part of the record source.
    var units = allUnits.where((u) => u.findAllElements('DATAVIEW_SRC').isNotEmpty).toList();
    if (units.isEmpty) {
      units = allUnits
          .where((u) =>
              u.findElements('Level').firstOrNull?.getAttribute('val') == 'R' &&
              u.findElements('Type').firstOrNull?.getAttribute('val') == 'M')
          .toList();
    }
    if (units.isEmpty) units = allUnits.toList();

    for (final unit in units) {
      final logicLines = unit.findElements('LogicLines').firstOrNull?.findElements('LogicLine');
      if (logicLines == null) continue;

      String currentTableObj = mainTableObj;
      String currentAlias = mainTableAlias;
      int currentJoinIndex = -1;
      final stack = <_LinkContext>[];

      for (final line in logicLines) {
        final op = line.children.whereType<XmlElement>().firstOrNull;
        if (op == null) continue;

        switch (op.name.local) {
          case 'DATAVIEW_SRC':
            currentTableObj = mainTableObj;
            currentAlias = mainTableAlias;
            currentJoinIndex = -1;
            stack.clear();
            break;

          case 'LNK':
            stack.add(_LinkContext(currentTableObj, currentAlias, currentJoinIndex));

            final linkedObj = _tableKeyOf(op.findElements('DB').firstOrNull);
            final mode = op.getAttribute('Mode') ?? 'R';
            final indexId = op.getAttribute('Key') ?? '';
            final linkedName = schemaService.getTableName(linkedObj);
            final linkedAlias = _allocateAlias(linkedName, aliasCounts);

            joins.add(TableJoin(
              joinType: _joinTypeForMode(mode),
              targetTableObj: linkedObj,
              targetTableName: linkedName,
              alias: linkedAlias,
              mode: mode,
              conditions: [],
              indexId: indexId,
              indexIsUnique: schemaService.isUniqueIndex(linkedObj, indexId),
              indexOrder: [
                for (final term in schemaService.getIndexOrder(linkedObj, indexId))
                  OrderByTerm(
                    tableName: linkedAlias,
                    colName: term.colName,
                    descending: term.descending,
                  ),
              ],
              descending: op.getAttribute('Direction') == 'D',
              isSqlSource: linkedObj.isEmpty || schemaService.isSqlTable(linkedObj),
            ));
            currentJoinIndex = joins.length - 1;
            currentTableObj = linkedObj;
            currentAlias = linkedAlias;
            break;

          case 'END_LINK':
            if (stack.isNotEmpty) {
              final restored = stack.removeLast();
              currentTableObj = restored.tableObj;
              currentAlias = restored.tableAlias;
              currentJoinIndex = restored.joinIndex;
            } else {
              currentTableObj = mainTableObj;
              currentAlias = mainTableAlias;
              currentJoinIndex = -1;
            }
            break;

          case 'Select':
            records.add(_readSelect(op, currentTableObj, currentAlias, currentJoinIndex));
            break;
        }
      }
    }

    return records;
  }

  /// Reads a `<DB>` element into a schema table key. The `comp` attribute
  /// names the owning component: -1 is this application, anything else is an
  /// external component whose object ids are a separate namespace.
  static String _tableKeyOf(XmlElement? dbNode) {
    if (dbNode == null) return '';
    final dataObject = dbNode.findElements('DataObject').firstOrNull;
    final obj = dbNode.getAttribute('obj') ?? dataObject?.getAttribute('obj') ?? '';
    if (obj.isEmpty || obj == '0') return '';
    final comp = dbNode.getAttribute('comp') ?? dataObject?.getAttribute('comp') ?? '-1';
    return SchemaService.tableKey(comp, obj);
  }

  /// Gives each table instance a distinct alias: the first use of a table keeps
  /// its name, later uses become `name_2`, `name_3` and so on.
  static String _allocateAlias(String tableName, Map<String, int> counts) {
    if (tableName.isEmpty) return '';
    final next = (counts[tableName] ?? 0) + 1;
    counts[tableName] = next;
    return next == 1 ? tableName : '${tableName}_$next';
  }

  /// Update operations live in the task's handler logic units, not the
  /// dataview, so every unit of this task has to be searched. Nested tasks are
  /// excluded because `TaskLogic` is read as a direct child only.
  Iterable<XmlElement> _updateOperations(XmlElement taskNode) sync* {
    final units = taskNode.findElements('TaskLogic').firstOrNull?.findElements('LogicUnit');
    if (units == null) return;
    for (final unit in units) {
      final lines = unit.findElements('LogicLines').firstOrNull?.findElements('LogicLine');
      if (lines == null) continue;
      for (final line in lines) {
        final update = line.findElements('Update').firstOrNull;
        if (update != null) yield update;
      }
    }
  }

  _SelectRecord _readSelect(
    XmlElement op,
    String tableObj,
    String tableAlias,
    int joinIndex,
  ) {
    final typeVal = op.findElements('Type').firstOrNull?.getAttribute('val') ?? 'V';

    final filters = <_FilterSpec>[];
    for (final node in [...op.findElements('Locate'), ...op.findElements('Range')]) {
      final min = node.getAttribute('MIN') ?? '';
      final max = node.getAttribute('MAX') ?? '';
      if (min.isEmpty && max.isEmpty) continue;
      filters.add(_FilterSpec(node.name.local, min, max));
    }

    return _SelectRecord(
      fieldId: op.getAttribute('FieldID') ?? '',
      typeVal: typeVal,
      colVal: op.findElements('Column').firstOrNull?.getAttribute('val') ?? '',
      isParameterFlag: op.findElements('IsParameter').firstOrNull?.getAttribute('val') == 'Y',
      tableObj: typeVal == 'R' ? tableObj : '',
      tableAlias: typeVal == 'R' ? tableAlias : '',
      joinIndex: typeVal == 'R' ? joinIndex : -1,
      assExpId: op.findElements('ASS').firstOrNull?.getAttribute('val') ?? '',
      realVarName: op.findElements('REAL_VNAME_TXT').firstOrNull?.getAttribute('val') ?? '',
      partOfDataview:
          op.findElements('PartOfDataview').firstOrNull?.getAttribute('val') != 'N',
      filters: filters,
    );
  }

  static String _joinTypeForMode(String mode) {
    switch (mode) {
      case 'J':
        return 'INNER JOIN';
      case 'O':
        return 'LEFT OUTER JOIN';
      case 'W':
      case 'A':
        return 'INNER JOIN';
      case 'R':
      default:
        // Link Query: at most the first matching record.
        return 'LEFT OUTER JOIN';
    }
  }

  // ---------------------------------------------------------------------------
  // Conditions
  // ---------------------------------------------------------------------------

  /// Returns (lowerExpression, upperExpression, operator), or null when the
  /// filter references an expression that does not exist.
  (String, String, String)? _buildCondition({
    required _FilterSpec filter,
    required String Function(String) resolve,
    required Map<String, String> expMap,
  }) {
    final hasMin = filter.minExpId.isNotEmpty && expMap.containsKey(filter.minExpId);
    final hasMax = filter.maxExpId.isNotEmpty && expMap.containsKey(filter.maxExpId);

    if (hasMin && hasMax) {
      if (filter.minExpId == filter.maxExpId) {
        final value = resolve(filter.minExpId);
        return value.isEmpty ? null : (value, '', '=');
      }
      final lower = resolve(filter.minExpId);
      final upper = resolve(filter.maxExpId);
      if (lower.isEmpty || upper.isEmpty) return null;
      return (lower, upper, 'BETWEEN');
    }
    if (hasMin) {
      final value = resolve(filter.minExpId);
      return value.isEmpty ? null : (value, '', '>=');
    }
    if (hasMax) {
      final value = resolve(filter.maxExpId);
      return value.isEmpty ? null : (value, '', '<=');
    }
    return null;
  }

  void _registerImplicitParameters(
    String expression,
    List<ProgramParameter> into,
    Map<String, String> typeByName,
  ) {
    for (final m in RegExp(r'@([A-Za-z_][A-Za-z0-9_]*)').allMatches(expression)) {
      final name = m.group(1)!;
      if (name.startsWith('Field_')) continue;
      if (into.any((p) => p.name == name)) continue;
      // Main Program globals already have a declared type; prefer it over the
      // fallback so the same global is not declared differently per program.
      final globalType = _mainProgramGlobals.values
          .where((g) => g.name == name)
          .map((g) => g.sqlType)
          .firstOrNull;
      into.add(ProgramParameter(
        fieldId: '',
        colId: '',
        name: name,
        type: typeByName[name] ?? globalType ?? 'NVARCHAR(255)',
        isParameter: true,
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Explicit SQL WHERE
  // ---------------------------------------------------------------------------

  /// Rebuilds the task's hand-written SQL WHERE from its token stream.
  /// CODE 1 substitutes a variable's value, CODE 2 a field's column name and
  /// CODE 3 is literal text.
  String _parseSqlWhere(
    XmlElement taskNode,
    Map<String, String> fieldRefs,
    Map<String, SelectedColumn> columnByField,
  ) {
    final whereNode = taskNode.findElements('SQL_WHERE_U').firstOrNull;
    if (whereNode == null) return '';

    final buffer = StringBuffer();
    for (final token in whereNode.findElements('TOKEN')) {
      final code = token.findElements('CODE').firstOrNull?.getAttribute('val') ?? '';
      final varIsn = token.findElements('VAR_ISN').firstOrNull?.getAttribute('val') ?? '';

      switch (code) {
        case '1':
          buffer.write(fieldRefs[varIsn] ?? '@Param_$varIsn');
          break;
        case '2':
          final column = columnByField[varIsn];
          if (column != null) {
            buffer.write('[${column.tableName}].[${column.colName}]');
          } else {
            buffer.write(fieldRefs[varIsn] ?? '/* field $varIsn */');
          }
          break;
        case '3':
          buffer.write(token.findElements('STR_U').firstOrNull?.getAttribute('val') ?? '');
          break;
      }
    }

    return buffer.toString().trim();
  }

  // ---------------------------------------------------------------------------
  // ORDER BY
  // ---------------------------------------------------------------------------

  List<OrderByTerm> _buildOrderBy({
    required XmlElement taskNode,
    required XmlElement? informationNode,
    required String mainTableObj,
    required String mainTableAlias,
    required List<_SelectRecord> records,
    required Map<String, SelectedColumn> columnByField,
  }) {
    // An explicit Sort block overrides the index order. Its segments address
    // dataview fields by position, not by ISN.
    final sortNode = informationNode?.findElements('Sort').firstOrNull;
    if (sortNode != null) {
      final terms = <OrderByTerm>[];
      for (final segment in sortNode.findElements('Segment')) {
        final position = int.tryParse(segment.findElements('Field').firstOrNull?.getAttribute('val') ?? '');
        if (position == null || position < 1 || position > records.length) continue;
        final column = columnByField[records[position - 1].fieldId];
        if (column == null) continue;
        terms.add(OrderByTerm(
          tableName: column.tableName,
          colName: column.colName,
          descending: segment.findElements('Direction').firstOrNull?.getAttribute('val') == 'D',
        ));
      }
      if (terms.isNotEmpty) return terms;
    }

    if (mainTableObj.isEmpty) return const [];

    // Otherwise the dataview is ordered by the index it reads through.
    String indexId = '';
    for (final src in taskNode.findAllElements('DATAVIEW_SRC')) {
      final idx = src.getAttribute('IDX');
      if (idx != null && idx.isNotEmpty) {
        indexId = idx;
        break;
      }
    }
    if (indexId.isEmpty) {
      indexId = informationNode
              ?.findElements('Key')
              .firstOrNull
              ?.findElements('Column')
              .firstOrNull
              ?.getAttribute('val') ??
          '';
    }
    if (indexId.isEmpty) return const [];

    final descending = informationNode?.findElements('Locate').firstOrNull?.getAttribute('Direction') == 'D';
    return [
      for (final term in schemaService.getIndexOrder(mainTableObj, indexId))
        OrderByTerm(
          tableName: mainTableAlias,
          colName: term.colName,
          descending: descending ? !term.descending : term.descending,
        ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Expressions
  // ---------------------------------------------------------------------------

  /// Rewrites `{generation,field}` references into SQL. Generation 0 is the
  /// current task, 1 the parent, 2 the grandparent, and 32768 the Main Program.
  String _resolveExpression(
    String expSyntax,
    Map<String, String> fieldRefs,
    List<Map<String, _AncestorField>> generationChain,
  ) {
    final resolved = expSyntax.replaceAllMapped(RegExp(r'\{(\d+)\s*,\s*(\d+)\}'), (match) {
      final generation = match.group(1)!;
      final fieldId = match.group(2)!;

      if (generation == kGlobalGeneration) {
        final global = _mainProgramGlobals[fieldId];
        return global != null ? '@${global.name}' : '@Global_$fieldId';
      }

      final level = int.tryParse(generation) ?? 0;
      if (level == 0) {
        final ref = fieldRefs[fieldId];
        if (ref != null) return ref;
      } else if (level - 1 < generationChain.length) {
        final ancestor = generationChain[level - 1][fieldId];
        if (ancestor != null) return ancestor.ref;
      }

      // Unresolvable generations happen when a task references a field of an
      // ancestor that is not part of this file.
      final global = _mainProgramGlobals[fieldId];
      if (global != null) return '@${global.name}';
      return '@Param_$fieldId';
    });

    return _translateToTsql(resolved);
  }

  /// Translates the uniPaaS operators and functions that map cleanly onto
  /// T-SQL. Anything unrecognised is passed through unchanged so the output
  /// stays comparable with the original expression.
  static String _translateToTsql(String expression) {
    final buffer = StringBuffer();
    var i = 0;

    while (i < expression.length) {
      final ch = expression[i];

      // String literals, including uniPaaS typed literals such as 'TRUE'LOG
      // and '01/01/1901'DATE.
      if (ch == "'") {
        final end = _endOfStringLiteral(expression, i);
        final literal = expression.substring(i, end);
        var j = end;
        while (j < expression.length && _isIdentifierPart(expression[j])) {
          j++;
        }
        final suffix = expression.substring(end, j).toUpperCase();
        buffer.write(_translateTypedLiteral(literal, suffix));
        i = j;
        continue;
      }

      // String concatenation.
      if (ch == '&') {
        buffer.write('+');
        i++;
        continue;
      }

      if (_isIdentifierStart(ch)) {
        var j = i;
        while (j < expression.length && _isIdentifierPart(expression[j])) {
          j++;
        }
        final word = expression.substring(i, j);
        buffer.write(_translateIdentifier(word));
        i = j;
        continue;
      }

      buffer.write(ch);
      i++;
    }

    return buffer.toString();
  }

  /// uniPaaS writes typed constants as a quoted body plus a type suffix.
  /// Logical constants become bit literals; dates and times keep their text but
  /// are cast so SQL Server reads them unambiguously.
  static String _translateTypedLiteral(String literal, String suffix) {
    if (suffix.isEmpty) return literal;

    final body = literal.length >= 2 ? literal.substring(1, literal.length - 1) : '';
    switch (suffix) {
      case 'LOG':
        return body.toUpperCase() == 'TRUE' ? '1' : '0';
      case 'DATE':
        // uniPaaS uses 00/00/0000 and 01/01/1901 as its null date sentinels.
        if (body.isEmpty || body.startsWith('00/00/') || body == '01/01/1901') {
          return 'NULL';
        }
        return "CONVERT(DATETIME, '$body', 103)";
      case 'TIME':
        if (body.isEmpty) return 'NULL';
        return "CONVERT(TIME, '$body')";
      default:
        // BLOB, VAR, EXP and friends have no literal SQL form; keep them
        // visible so the difference from uniPaaS is obvious.
        return '$literal$suffix';
    }
  }

  static int _endOfStringLiteral(String s, int start) {
    var i = start + 1;
    while (i < s.length) {
      if (s[i] == "'") {
        if (i + 1 < s.length && s[i + 1] == "'") {
          i += 2;
          continue;
        }
        return i + 1;
      }
      i++;
    }
    return s.length;
  }

  static bool _isIdentifierStart(String c) =>
      RegExp(r'[A-Za-z_]').hasMatch(c);

  static bool _isIdentifierPart(String c) =>
      RegExp(r'[A-Za-z0-9_]').hasMatch(c);

  /// uniPaaS function and keyword names that have a same-shaped T-SQL
  /// equivalent. Everything else keeps its uniPaaS spelling so the difference
  /// from the original expression stays visible.
  static const Map<String, String> _identifierTranslations = {
    'TRIM': 'TRIM',
    'UPPER': 'UPPER',
    'LOWER': 'LOWER',
    'AND': 'AND',
    'OR': 'OR',
    'NOT': 'NOT',
    'ABS': 'ABS',
    'ROUND': 'ROUND',
    'REPSTR': 'REPLACE',
    // InStr is deliberately not mapped to CHARINDEX: uniPaaS takes
    // (haystack, needle) and T-SQL takes (needle, haystack), so renaming it
    // would silently invert the arguments.
  };

  static String _translateIdentifier(String word) =>
      _identifierTranslations[word.toUpperCase()] ?? word;
}
