class ProgramParameter {
  final String fieldId;
  final String colId;
  final String name;
  final String type;
  final bool isParameter;
  String currentValue;

  ProgramParameter({
    required this.fieldId,
    required this.colId,
    required this.name,
    required this.type,
    required this.isParameter,
    this.currentValue = '',
  });

  factory ProgramParameter.fromJson(Map<String, dynamic> json) {
    return ProgramParameter(
      fieldId: json['fieldId']?.toString() ?? '',
      colId: json['colId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? 'ALPHA',
      isParameter: json['isParameter'] == true,
      currentValue: '',
    );
  }

  ProgramParameter copyWith({String? currentValue}) {
    return ProgramParameter(
      fieldId: fieldId,
      colId: colId,
      name: name,
      type: type,
      isParameter: isParameter,
      currentValue: currentValue ?? this.currentValue,
    );
  }
}

class ProgramMetadata {
  final String id;
  final String filename;
  final String name;
  final List<ProgramParameter> parameters;
  final bool hasTables;

  ProgramMetadata({
    required this.id,
    required this.filename,
    required this.name,
    required this.parameters,
    this.hasTables = true,
  });

  factory ProgramMetadata.fromJson(Map<String, dynamic> json) {
    var paramsList = (json['parameters'] as List<dynamic>?) ?? [];
    return ProgramMetadata(
      id: json['id']?.toString() ?? '',
      filename: json['filename']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      parameters: paramsList.map((x) => ProgramParameter.fromJson(x)).toList(),
      hasTables: json['hasTables'] == null ? true : (json['hasTables'] == true),
    );
  }

  ProgramMetadata copyWith({
    String? id,
    String? filename,
    String? name,
    List<ProgramParameter>? parameters,
    bool? hasTables,
  }) {
    return ProgramMetadata(
      id: id ?? this.id,
      filename: filename ?? this.filename,
      name: name ?? this.name,
      parameters: parameters ?? this.parameters,
      hasTables: hasTables ?? this.hasTables,
    );
  }
}

class SelectedColumn {
  final String fieldId;
  final String tableObj;
  final String tableName;
  final String colId;
  final String colName;
  final String alias;
  final String initExpression;

  SelectedColumn({
    required this.fieldId,
    required this.tableObj,
    required this.tableName,
    required this.colId,
    required this.colName,
    required this.alias,
    this.initExpression = '',
  });
}

class JoinCondition {
  final String targetColName;
  final String sourceExpression;

  JoinCondition({
    required this.targetColName,
    required this.sourceExpression,
  });
}

class TableJoin {
  final String joinType;
  final String targetTableObj;
  final String targetTableName;
  final String mode;
  final List<JoinCondition> conditions;

  TableJoin({
    required this.joinType,
    required this.targetTableObj,
    required this.targetTableName,
    this.mode = 'R',
    required this.conditions,
  });
}

class WhereCondition {
  final String tableName;
  final String colName;
  final String operator;
  final String valueExpression;

  WhereCondition({
    required this.tableName,
    required this.colName,
    required this.operator,
    required this.valueExpression,
  });
}

class ParsedTask {
  final String taskId;
  final String taskIsn;
  final String? parentTaskId;
  final int level;
  final String description;
  final String mainTableObj;
  final String mainTableName;
  final List<SelectedColumn> columns;
  final List<TableJoin> joins;
  final List<WhereCondition> whereConditions;
  final List<ProgramParameter> parameters;
  final List<ParsedTask> subTasks;

  ParsedTask({
    required this.taskId,
    this.taskIsn = '1',
    this.parentTaskId,
    this.level = 0,
    required this.description,
    required this.mainTableObj,
    required this.mainTableName,
    required this.columns,
    required this.joins,
    required this.whereConditions,
    this.parameters = const [],
    this.subTasks = const [],
  });

  bool get isChild => level > 0 || (parentTaskId != null && parentTaskId!.isNotEmpty);

  List<ParsedTask> get allDescendantsFlattened {
    final list = <ParsedTask>[this];
    for (final child in subTasks) {
      list.addAll(child.allDescendantsFlattened);
    }
    return list;
  }
}

class ParsedProgram {
  final String id;
  final String filename;
  final String name;
  final List<ParsedTask> tasks;
  final List<ProgramParameter> extractedParameters;

  ParsedProgram({
    required this.id,
    required this.filename,
    required this.name,
    required this.tasks,
    this.extractedParameters = const [],
  });

  List<ParsedTask> get allTasksFlattened {
    final list = <ParsedTask>[];
    for (final task in tasks) {
      list.addAll(task.allDescendantsFlattened);
    }
    return list;
  }

  bool get hasTables {
    return allTasksFlattened.any((t) => (t.mainTableObj.isNotEmpty && t.mainTableObj != '0') || t.joins.isNotEmpty);
  }
}

