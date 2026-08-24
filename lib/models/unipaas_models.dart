class GlobalVarInfo {
  final String fieldId;
  final String name;
  final String sqlType;

  GlobalVarInfo({
    required this.fieldId,
    required this.name,
    required this.sqlType,
  });
}

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

/// Translates a uniPaaS field definition into a SQL Server type. Shared by the
/// program parser and the DataSources reader so both agree.
class UnipaasTypeMapper {
  static String sqlType({
    required String attrObj,
    String picture = '',
    int whole = 0,
    int dec = 0,
    int size = 0,
  }) {
    switch (attrObj.toUpperCase()) {
      case 'FIELD_NUMERIC':
        if (dec > 0) {
          // uniPaaS counts whole and decimal digits separately; SQL Server
          // wants total precision, which must be at least the scale.
          final precision = (whole > 0 ? whole : 18) + dec;
          return 'DECIMAL(${precision > 38 ? 38 : precision}, $dec)';
        }
        if (whole > 9) return 'BIGINT';
        return 'INT';
      case 'FIELD_ALPHA':
      case 'FIELD_UNICODE':
        // A picture such as "U10" is a unicode field of length 10.
        final digits = RegExp(r'(\d+)').firstMatch(picture)?.group(1);
        var len = digits != null ? int.parse(digits) : (size > 0 ? size : 255);
        if (len <= 0) len = 255;
        return len > 4000 ? 'NVARCHAR(MAX)' : 'NVARCHAR($len)';
      case 'FIELD_DATE':
        return 'DATETIME';
      case 'FIELD_TIME':
        return 'TIME';
      case 'FIELD_LOGICAL':
        return 'BIT';
      case 'FIELD_BLOB':
        return 'NVARCHAR(MAX)';
      default:
        final digits = RegExp(r'(\d+)').firstMatch(picture)?.group(1);
        if (digits != null) {
          final len = int.parse(digits);
          return len > 4000 ? 'NVARCHAR(MAX)' : 'NVARCHAR($len)';
        }
        return 'NVARCHAR(255)';
    }
  }
}

/// One column of a data object, as described by DataSources.xml.
class SchemaColumn {
  final String id; // column ISN (the `id` attribute)
  final String name; // logical/model name
  final String dbColumnName; // physical name used in SQL
  final String sqlType;

  SchemaColumn({
    required this.id,
    required this.name,
    required this.dbColumnName,
    this.sqlType = 'NVARCHAR(255)',
  });
}

/// A segment of a database index. [columnIsn] has already been translated from
/// the positional reference DataSources.xml uses into a column ISN.
class IndexSegment {
  final String columnIsn;
  final bool descending;

  IndexSegment({required this.columnIsn, this.descending = false});
}

class SchemaIndex {
  final String id;
  final String name;
  final List<IndexSegment> segments;

  /// Primary or single-mode index. A Link Query over a unique index returns at
  /// most one row, so it can be expressed as a plain LEFT JOIN.
  final bool unique;

  SchemaIndex({
    required this.id,
    required this.name,
    required this.segments,
    this.unique = false,
  });
}

class SchemaTable {
  final String id; // data object id (the `obj` referenced by tasks)
  final String name; // logical name
  final String physicalName; // real table name in the database
  final String dataSource; // connection name, e.g. MyFlo / Memory
  final bool isView;
  final Map<String, SchemaColumn> columnsByIsn;
  final List<SchemaColumn> columnsInOrder;
  final Map<String, SchemaIndex> indexesById;

  SchemaTable({
    required this.id,
    required this.name,
    required this.physicalName,
    required this.dataSource,
    this.isView = false,
    required this.columnsByIsn,
    required this.columnsInOrder,
    required this.indexesById,
  });

  /// DataSources.xml refers to columns by 1-based position inside index
  /// segments, but tasks refer to them by ISN. This bridges the two.
  String? columnIsnAtPosition(int position) {
    if (position < 1 || position > columnsInOrder.length) return null;
    return columnsInOrder[position - 1].id;
  }
}

class SelectedColumn {
  final String fieldId;
  final String tableObj;

  /// Alias the column is qualified with. A task may link the same table more
  /// than once, so this is not necessarily the table name.
  final String tableName;

  /// Real table name behind [tableName].
  final String tableRealName;
  final String colId;
  final String colName;
  final String alias;
  final String initExpression;

  SelectedColumn({
    required this.fieldId,
    required this.tableObj,
    required this.tableName,
    String? tableRealName,
    required this.colId,
    required this.colName,
    required this.alias,
    this.initExpression = '',
  }) : tableRealName = tableRealName ?? tableName;
}

class JoinCondition {
  final String targetColName;
  final String sourceExpression;

  /// '=', '>=', '<=' or 'BETWEEN'. Ranges inside a link are real filters and
  /// must not be flattened into equality.
  final String operator;

  /// Upper bound, only meaningful when [operator] is 'BETWEEN'.
  final String upperExpression;

  JoinCondition({
    required this.targetColName,
    required this.sourceExpression,
    this.operator = '=',
    this.upperExpression = '',
  });
}

class TableJoin {
  final String joinType;
  final String targetTableObj;
  final String targetTableName;

  /// Alias this link instance is addressed by, which differs from
  /// [targetTableName] when the same table is linked more than once.
  final String alias;

  /// Raw uniPaaS link mode: R=Link Query, O=Left Outer, J=Inner, W=Write,
  /// A=Create.
  final String mode;
  final List<JoinCondition> conditions;

  /// Index the link reads through, and whether that index is unique.
  final String indexId;
  final bool indexIsUnique;

  /// Columns of that index, in order. Used to make "first matching record"
  /// deterministic when the link is expressed as a TOP 1.
  final List<OrderByTerm> indexOrder;

  /// Descending link direction, which flips which record a Link Query keeps.
  final bool descending;

  final bool isSqlSource;

  TableJoin({
    required this.joinType,
    required this.targetTableObj,
    required this.targetTableName,
    String? alias,
    this.mode = 'R',
    required this.conditions,
    this.indexId = '',
    this.indexIsUnique = false,
    this.indexOrder = const [],
    this.descending = false,
    this.isSqlSource = true,
  }) : alias = alias ?? targetTableName;

  /// True when the alias differs from the table name and must be spelled out.
  bool get needsAlias => alias != targetTableName;

  /// The link matches at most one row only if it reads a unique index and
  /// binds every segment of it.
  bool get matchesAtMostOneRow =>
      indexIsUnique && indexOrder.isNotEmpty && conditions.length >= indexOrder.length;

  bool get isWrite => mode == 'W' || mode == 'A';

  /// A Link Query keeps only the first matching record. When the link is
  /// guaranteed to match at most one row that is exactly a LEFT JOIN;
  /// otherwise a plain join would multiply rows and it needs
  /// OUTER APPLY (SELECT TOP 1 ...).
  bool get needsTopOneApply => mode == 'R' && !matchesAtMostOneRow;
}

class WhereCondition {
  final String tableName;
  final String colName;
  final String operator;
  final String valueExpression;

  /// Upper bound, only meaningful when [operator] is 'BETWEEN'.
  final String upperExpression;

  /// Set for conditions that came from a main-source Locate rather than a
  /// Range, so the generated SQL can say where they came from.
  final String origin;

  WhereCondition({
    required this.tableName,
    required this.colName,
    required this.operator,
    required this.valueExpression,
    this.upperExpression = '',
    this.origin = 'Range',
  });
}

/// A value written to a column by an Update operation in the task's logic.
class ColumnAssignment {
  final String fieldId;
  final String tableObj;
  final String tableAlias;
  final String tableName;
  final String colName;
  final String expression;

  /// `Incremental` updates add to the current value instead of replacing it.
  final bool incremental;

  ColumnAssignment({
    required this.fieldId,
    required this.tableObj,
    required this.tableAlias,
    required this.tableName,
    required this.colName,
    required this.expression,
    this.incremental = false,
  });
}

class OrderByTerm {
  final String tableName;
  final String colName;
  final bool descending;

  OrderByTerm({
    required this.tableName,
    required this.colName,
    this.descending = false,
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

  /// Alias the main source is qualified with; equal to [mainTableName] unless
  /// the same table is also linked.
  final String mainTableAlias;
  final List<SelectedColumn> columns;
  final List<TableJoin> joins;
  final List<WhereCondition> whereConditions;
  final List<ProgramParameter> parameters;
  final List<ParsedTask> subTasks;

  /// Verbatim WHERE fragment built from the task's SQL_WHERE_U token stream.
  final String sqlWhereClause;

  /// Values the task writes to columns, from its Update operations.
  final List<ColumnAssignment> assignments;

  /// Initial task mode: M=Modify, C=Create, D=Delete, Q=Query.
  final String initialMode;

  /// Tables owned by another uniPaaS component. Comps.xml gives their names
  /// but not their columns, so those stay unresolved.
  final List<String> externalTables;

  /// Derived from the main source index (or an explicit Sort block).
  final List<OrderByTerm> orderBy;

  /// Connection the main source lives on, e.g. MyFlo. Memory and XML sources
  /// are not real SQL tables.
  final String dataSource;
  final bool mainSourceIsSql;

  ParsedTask({
    required this.taskId,
    this.taskIsn = '1',
    this.parentTaskId,
    this.level = 0,
    required this.description,
    required this.mainTableObj,
    required this.mainTableName,
    String? mainTableAlias,
    required this.columns,
    required this.joins,
    required this.whereConditions,
    this.parameters = const [],
    this.subTasks = const [],
    this.sqlWhereClause = '',
    this.assignments = const [],
    this.initialMode = '',
    this.externalTables = const [],
    this.orderBy = const [],
    this.dataSource = '',
    this.mainSourceIsSql = true,
  }) : mainTableAlias = mainTableAlias ?? mainTableName;

  bool get isChild => level > 0 || (parentTaskId != null && parentTaskId!.isNotEmpty);

  bool get hasDataSource =>
      (mainTableObj.isNotEmpty && mainTableObj != '0') || joins.isNotEmpty;

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
  final Map<String, GlobalVarInfo> mainProgramGlobals;

  ParsedProgram({
    required this.id,
    required this.filename,
    required this.name,
    required this.tasks,
    this.extractedParameters = const [],
    this.mainProgramGlobals = const {},
  });

  List<ParsedTask> get allTasksFlattened {
    final list = <ParsedTask>[];
    for (final task in tasks) {
      list.addAll(task.allDescendantsFlattened);
    }
    return list;
  }

  bool get hasTables => allTasksFlattened.any((t) => t.hasDataSource);
}
