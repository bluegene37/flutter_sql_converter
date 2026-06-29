import 'dart:io';
import 'package:xml/xml.dart';
import '../models/unipaas_models.dart';
import 'schema_service.dart';

class XmlParserService {
  final SchemaService schemaService;

  XmlParserService(this.schemaService);

  Future<ParsedProgram?> parseProgramFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    final xmlString = await file.readAsString();
    return parseProgramString(xmlString, filePath);
  }

  ParsedProgram? parseProgramString(String xmlString, String filename) {
    try {
      final doc = XmlDocument.parse(xmlString);
      final tasks = <ParsedTask>[];
      final extractedParameters = <ProgramParameter>[];

      String progId = '';
      String progName = filename;

      final idMatch = RegExp(r'Prg_(\d+)\.xml').firstMatch(filename);
      if (idMatch != null) {
        progId = idMatch.group(1)!;
      }

      final taskNodes = doc.findAllElements('Task');
      for (final taskNode in taskNodes) {
        final headerNode = taskNode.findElements('Header').firstOrNull;
        String taskId = '';
        String taskDesc = 'Task';
        if (headerNode != null) {
          taskId = headerNode.getAttribute('id') ?? '';
          taskDesc = headerNode.getAttribute('Description') ?? 'Task $taskId';
          if (progId.isEmpty && taskId.isNotEmpty) progId = taskId;
          if (progName == filename && taskDesc.isNotEmpty) progName = taskDesc;
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
        final varMap = <String, String>{}; // colId -> name
        final colNodes = taskNode.findElements('Resource').firstOrNull?.findAllElements('Column');
        if (colNodes != null) {
          for (final col in colNodes) {
            final cId = col.getAttribute('id') ?? '';
            final cName = col.getAttribute('name') ?? 'Var_$cId';
            varMap[cId] = cName;
          }
        }

        // FieldID to Variable/Parameter mapping
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
              final rawVarName = varMap[colVal] ?? '';
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
                  initExpr = rawExpr.replaceAllMapped(RegExp(r'\{0,(\d+)\}'), (match) {
                    final refFieldId = match.group(1)!;
                    if (fieldToVarName.containsKey(refFieldId)) {
                      return '@${fieldToVarName[refFieldId]}';
                    } else if (fieldMap.containsKey(refFieldId)) {
                      final refCol = fieldMap[refFieldId]!;
                      return '[${refCol.tableName}].[${refCol.colName}]';
                    } else {
                      return '@Param_$refFieldId';
                    }
                  });
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

                    String resolvedExpression = expSyntax.replaceAllMapped(RegExp(r'\{0,(\d+)\}'), (match) {
                      final refFieldId = match.group(1)!;
                      if (fieldToVarName.containsKey(refFieldId)) {
                        return '@${fieldToVarName[refFieldId]}';
                      } else if (fieldMap.containsKey(refFieldId)) {
                        final refCol = fieldMap[refFieldId]!;
                        return '[${refCol.tableName}].[${refCol.colName}]';
                      } else {
                        return '@Param_$refFieldId';
                      }
                    });

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

        tasks.add(ParsedTask(
          taskId: taskId,
          description: taskDesc,
          mainTableObj: mainTableObj,
          mainTableName: mainTableName,
          columns: selectedColumns,
          joins: joins,
          whereConditions: whereConditions,
          parameters: taskParameters,
        ));
      }

      return ParsedProgram(
        id: progId,
        filename: filename,
        name: progName,
        tasks: tasks,
        extractedParameters: extractedParameters,
      );
    } catch (e) {
      // ignore: avoid_print
      print('Error parsing XML string: $e');
      return null;
    }
  }
}
