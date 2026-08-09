import 'dart:io';
import 'package:xml/xml.dart';
import '../models/unipaas_models.dart';
import 'schema_service.dart';

class XmlParserService {
  final SchemaService schemaService;
  final Map<String, String> _mainProgramFieldMap = {};

  XmlParserService(this.schemaService);

  Future<ParsedProgram?> parseProgramFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    final sourceDir = file.parent.path;
    await ensureMainProgramLoaded(sourceDir);

    final xmlString = await file.readAsString();
    return parseProgramString(xmlString, filePath);
  }

  Future<void> ensureMainProgramLoaded(String sourceDir) async {
    if (_mainProgramFieldMap.isNotEmpty) return;

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
              if (_mainProgramFieldMap.isNotEmpty) return;
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
          if (_mainProgramFieldMap.isNotEmpty) break;
        } catch (_) {}
      }
    }
  }

  void _parseMainProgramGlobals(String xmlString) {
    try {
      final doc = XmlDocument.parse(xmlString);
      final mainTask = doc.findAllElements('Task').where((e) {
        return e.getAttribute('MainProgram') == 'Y' ||
            e.findElements('Header').firstOrNull?.getAttribute('Description') == 'Main Program';
      }).firstOrNull ?? doc.findAllElements('Task').firstOrNull;

      if (mainTask == null) return;

      final colIdMap = <String, String>{};
      final colIndexMap = <String, String>{};
      final colNodes = mainTask.findElements('Resource').firstOrNull?.findAllElements('Column');
      if (colNodes != null) {
        int idx = 1;
        for (final col in colNodes) {
          final cId = col.getAttribute('id') ?? '';
          final cName = col.getAttribute('name') ?? '';
          if (cName.isNotEmpty) {
            colIndexMap[idx.toString()] = cName;
            if (cId.isNotEmpty) {
              colIdMap[cId] = cName;
            }
          }
          idx++;
        }
      }

      final logicUnits = mainTask.findElements('TaskLogic').firstOrNull?.findElements('LogicUnit') ?? <XmlElement>[];
      for (final lu in logicUnits) {
        final logicLines = lu.findElements('LogicLines').firstOrNull?.findElements('LogicLine');
        if (logicLines == null) continue;
        for (final line in logicLines) {
          final selectNode = line.findElements('Select').firstOrNull;
          if (selectNode != null) {
            final fieldId = selectNode.getAttribute('FieldID') ?? '';
            final colVal = selectNode.findElements('Column').firstOrNull?.getAttribute('val') ?? '';
            final matchedName = colIndexMap[colVal] ?? colIdMap[colVal] ?? colIndexMap[fieldId];
            if (fieldId.isNotEmpty && matchedName != null) {
              _mainProgramFieldMap[fieldId] = matchedName;
            }
          }
        }
      }

      colIndexMap.forEach((idx, name) {
        if (!_mainProgramFieldMap.containsKey(idx)) {
          _mainProgramFieldMap[idx] = name;
        }
      });
    } catch (e) {
      // ignore: avoid_print
      print('Error parsing MainProgram globals: $e');
    }
  }

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

      // Find top-level Task nodes (under Programs or root)
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
      );
    } catch (e) {
      // ignore: avoid_print
      print('Error parsing XML string: $e');
      return null;
    }
  }

  ParsedTask? _parseSingleTask(
    XmlElement taskNode, {
    String? parentTaskId,
    int level = 0,
    required List<ProgramParameter> extractedParameters,
    Map<String, String> parentFieldMap = const {},
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

    // Main Table
    String mainTableObj = '';
    final infoDb = taskNode.findElements('Information').firstOrNull?.findElements('DB').firstOrNull;
    if (infoDb != null) {
      final dataObj = infoDb.findElements('DataObject').firstOrNull;
      mainTableObj = dataObj?.getAttribute('obj') ?? infoDb.getAttribute('obj') ?? '';
    }

    final mainTableName = schemaService.getTableName(mainTableObj);

    // Expressions
    final expMap = <String, String>{};
    final expNodes = taskNode.findElements('Expressions').firstOrNull?.findElements('Expression');
    if (expNodes != null) {
      int idx = 1;
      for (final exp in expNodes) {
        final syn = exp.findElements('ExpSyntax').firstOrNull?.getAttribute('val');
        if (syn != null) {
          expMap[idx.toString()] = syn;
        }
        idx++;
      }
    }

    // Variable definitions from Resource/Columns
    final varMap = <String, String>{}; // colId or ordinal index -> name
    final colNodes = taskNode.findElements('Resource').firstOrNull?.findAllElements('Column');
    if (colNodes != null) {
      int idx = 1;
      for (final col in colNodes) {
        final cId = col.getAttribute('id') ?? '';
        final cName = col.getAttribute('name') ?? 'Var_$idx';
        if (cId.isNotEmpty) varMap[cId] = cName;
        varMap[idx.toString()] = cName;
        idx++;
      }
    }

    final fieldToVarName = <String, String>{};
    final selectedColumns = <SelectedColumn>[];
    final joins = <TableJoin>[];
    final whereConditions = <WhereCondition>[];
    final taskParameters = <ProgramParameter>[];
    final fieldMap = <String, SelectedColumn>{};

    String currentTableObj = mainTableObj;
    final tableStack = <String>[];
    TableJoin? currentJoin;

    final logicUnits = taskNode.findElements('TaskLogic').firstOrNull?.findElements('LogicUnit') ?? <XmlElement>[];
    for (final lu in logicUnits) {
      final logicLines = lu.findElements('LogicLines').firstOrNull?.findElements('LogicLine');
      if (logicLines == null) continue;

      for (final line in logicLines) {
        final op = line.children.whereType<XmlElement>().firstOrNull;
        if (op == null) continue;

        if (op.name.local == 'DATAVIEW_SRC') {
          currentTableObj = mainTableObj;
          tableStack.clear();
        } else if (op.name.local == 'LNK') {
          tableStack.add(currentTableObj);
          final dbNode = op.findElements('DB').firstOrNull;
          if (dbNode != null) {
            currentTableObj = dbNode.getAttribute('obj') ?? '';
            if (currentTableObj.isEmpty) {
              currentTableObj = dbNode.findElements('DataObject').firstOrNull?.getAttribute('obj') ?? '';
            }
          }
          final mode = op.getAttribute('Mode') ?? 'R';
          final joinType = (mode == 'W') ? 'INNER JOIN' : 'LEFT OUTER JOIN';
          final targetTableName = schemaService.getTableName(currentTableObj);

          currentJoin = TableJoin(
            joinType: joinType,
            targetTableObj: currentTableObj,
            targetTableName: targetTableName,
            mode: mode,
            conditions: [],
          );
          joins.add(currentJoin);
        } else if (op.name.local == 'END_LINK') {
          if (tableStack.isNotEmpty) {
            currentTableObj = tableStack.removeLast();
          } else {
            currentTableObj = mainTableObj;
          }
          currentJoin = null;
        } else if (op.name.local == 'Select') {
          final fieldId = op.getAttribute('FieldID') ?? '';
          final colVal = op.findElements('Column').firstOrNull?.getAttribute('val') ?? '';
          final typeVal = op.findElements('Type').firstOrNull?.getAttribute('val') ?? 'U';
          final isParam = op.findElements('IsParameter').firstOrNull?.getAttribute('val') == 'Y';
          final rawVarName = varMap[colVal] ?? varMap[fieldId] ?? '';
          final isParamName = rawVarName.startsWith('p_') || rawVarName.startsWith('Param_');

          if (typeVal == 'V' && colVal.isNotEmpty) {
            final varName = rawVarName.isNotEmpty ? rawVarName : 'Var_$colVal';
            fieldToVarName[fieldId] = varName;
            final param = ProgramParameter(
              fieldId: fieldId,
              colId: colVal,
              name: varName,
              type: 'ALPHA',
              isParameter: isParam || isParamName,
            );
            if (!extractedParameters.any((p) => p.name == varName)) extractedParameters.add(param);
            if ((isParam || isParamName) && !taskParameters.any((p) => p.name == varName)) taskParameters.add(param);
          } else if (isParam || (isParamName && typeVal == 'R')) {
            final paramName = rawVarName.isNotEmpty ? rawVarName : 'Param_$fieldId';
            fieldToVarName[fieldId] = paramName;
            final param = ProgramParameter(
              fieldId: fieldId,
              colId: colVal,
              name: paramName,
              type: 'ALPHA',
              isParameter: true,
            );
            if (!extractedParameters.any((p) => p.name == paramName)) extractedParameters.add(param);
            if (!taskParameters.any((p) => p.name == paramName)) taskParameters.add(param);
          }

          final isRealCol = (typeVal == 'R' && !isParam && !isParamName);
          if (isRealCol && fieldId.isNotEmpty && colVal.isNotEmpty && currentTableObj.isNotEmpty) {
            final tName = schemaService.getTableName(currentTableObj);
            final cName = schemaService.getColumnName(currentTableObj, colVal);
            final cAlias = schemaService.getColumnAlias(currentTableObj, colVal, fallback: 'Field_$fieldId');

            final assVal = op.findElements('ASS').firstOrNull?.getAttribute('val') ?? '';
            final locVal = op.findElements('Locate').firstOrNull?.getAttribute('MIN') ?? '';
            final expKey = assVal.isNotEmpty ? assVal : locVal;
            String initExpr = '';
            if (expKey.isNotEmpty && expMap.containsKey(expKey)) {
              final rawExpr = expMap[expKey]!;
              initExpr = _resolveExpressionString(rawExpr, fieldToVarName, fieldMap, parentFieldMap);
            } else if (expKey.isNotEmpty) {
              initExpr = expKey;
            }

            final selCol = SelectedColumn(
              fieldId: fieldId,
              tableObj: currentTableObj,
              tableName: tName,
              colId: colVal,
              colName: cName,
              alias: cAlias,
              initExpression: initExpr,
            );
            fieldMap[fieldId] = selCol;

            if (currentTableObj.isNotEmpty) {
              selectedColumns.add(selCol);
            }
          }

          // Locate and Range conditions
          for (final condNode in [...op.findElements('Locate'), ...op.findElements('Range')]) {
            if (!isRealCol) continue;
            final minVal = condNode.getAttribute('MIN');
            final maxVal = condNode.getAttribute('MAX');

            final valsToCheck = <String, String>{};
            if (minVal != null && maxVal != null && minVal == maxVal) {
              valsToCheck[minVal] = '=';
            } else {
              if (minVal != null) valsToCheck[minVal] = '>=';
              if (maxVal != null) valsToCheck[maxVal] = '<=';
            }

            for (final entry in valsToCheck.entries) {
              final expKey = entry.key;
              final opStr = entry.value;
              if (expMap.containsKey(expKey)) {
                final expSyntax = expKey.isNotEmpty ? expMap[expKey]! : '';
                if (expSyntax.isEmpty) continue;
                final targetColName = schemaService.getColumnName(currentTableObj, colVal);

                String resolvedExpression = _resolveExpressionString(expSyntax, fieldToVarName, fieldMap, parentFieldMap);

                for (final m in RegExp(r'@([a-zA-Z0-9_()]+)').allMatches(resolvedExpression)) {
                  final paramName = m.group(1)!;
                  if (!paramName.startsWith('Field_') && !extractedParameters.any((p) => p.name == paramName)) {
                    extractedParameters.add(ProgramParameter(
                      fieldId: '',
                      colId: '',
                      name: paramName,
                      type: 'GLOBAL',
                      isParameter: true,
                    ));
                  }
                }

                if (currentJoin != null) {
                  currentJoin.conditions.add(JoinCondition(
                    targetColName: targetColName,
                    sourceExpression: resolvedExpression,
                  ));
                } else {
                  whereConditions.add(WhereCondition(
                    tableName: schemaService.getTableName(currentTableObj),
                    colName: targetColName,
                    operator: opStr,
                    valueExpression: resolvedExpression,
                  ));
                }
              }
            }
          }
        }
      }
    }

    // Combine current task's field names into map for children
    final combinedFieldMap = <String, String>{...parentFieldMap};
    fieldToVarName.forEach((fId, name) => combinedFieldMap[fId] = name);

    // Recursively parse direct child Task nodes
    final childTaskNodes = taskNode.children.whereType<XmlElement>().where((e) => e.name.local == 'Task');
    final parsedSubTasks = <ParsedTask>[];

    for (final childNode in childTaskNodes) {
      final childTask = _parseSingleTask(
        childNode,
        parentTaskId: taskId,
        level: level + 1,
        extractedParameters: extractedParameters,
        parentFieldMap: combinedFieldMap,
      );
      if (childTask != null) {
        parsedSubTasks.add(childTask);
      }
    }

    return ParsedTask(
      taskId: taskId,
      taskIsn: taskIsn,
      parentTaskId: parentTaskId,
      level: level,
      description: taskDesc,
      mainTableObj: mainTableObj,
      mainTableName: mainTableName,
      columns: selectedColumns,
      joins: joins,
      whereConditions: whereConditions,
      parameters: taskParameters,
      subTasks: parsedSubTasks,
    );
  }

  String _resolveExpressionString(
    String expSyntax,
    Map<String, String> fieldToVarName,
    Map<String, SelectedColumn> fieldMap,
    Map<String, String> parentFieldMap,
  ) {
    return expSyntax.replaceAllMapped(RegExp(r'\{(\d+)\s*,\s*(\d+)\}'), (match) {
      final taskIsn = match.group(1)!;
      final refFieldId = match.group(2)!;

      if (taskIsn == '32768' || taskIsn == '1') {
        if (_mainProgramFieldMap.containsKey(refFieldId)) {
          return '@${_mainProgramFieldMap[refFieldId]}';
        }
      }

      if (fieldToVarName.containsKey(refFieldId)) {
        return '@${fieldToVarName[refFieldId]}';
      } else if (fieldMap.containsKey(refFieldId)) {
        final refCol = fieldMap[refFieldId]!;
        return '[${refCol.tableName}].[${refCol.colName}]';
      } else if (parentFieldMap.containsKey(refFieldId)) {
        return '@${parentFieldMap[refFieldId]}';
      } else if (_mainProgramFieldMap.containsKey(refFieldId)) {
        return '@${_mainProgramFieldMap[refFieldId]}';
      } else {
        return '@Param_$refFieldId';
      }
    });
  }
}
