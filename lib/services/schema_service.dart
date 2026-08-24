import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:xml/xml_events.dart';
import '../models/unipaas_models.dart';

/// Connections that are not backed by a real SQL server. Tasks whose main
/// source lives on one of these cannot be turned into a runnable query.
const Set<String> _nonSqlDataSources = {
  'Memory',
  'Default XML Database',
  'SQLite Database',
  'Email',
  'Google',
};

class SchemaService {
  final Map<String, SchemaTable> _tables = {};
  final List<ProgramMetadata> _programs = [];
  bool _isLoaded = false;
  final Set<String> _loadedDataSourcesPaths = {};

  bool get isLoaded => _isLoaded;
  List<ProgramMetadata> get programs => _programs;
  Map<String, SchemaTable> get tables => _tables;

  Future<void> loadSchema([String? customJsonPath]) async {
    String jsonString;
    if (customJsonPath != null && File(customJsonPath).existsSync()) {
      jsonString = await File(customJsonPath).readAsString();
    } else {
      jsonString = await rootBundle.loadString('assets/schema_data.json');
    }

    final data = json.decode(jsonString) as Map<String, dynamic>;

    _tables.clear();

    final tables = data['tables'] as List<dynamic>? ?? [];
    for (final t in tables) {
      final tObj = t['id']?.toString() ?? '';
      if (tObj.isEmpty) continue;
      final tName = t['name']?.toString() ?? '';

      final columnsByIsn = <String, SchemaColumn>{};
      final columnsInOrder = <SchemaColumn>[];

      final cols = t['columns'] as List<dynamic>? ?? [];
      for (final c in cols) {
        final cId = c['id']?.toString() ?? '';
        final rawName = c['name']?.toString() ?? '';
        final dbCol = c['dbColumnName']?.toString().trim() ?? '';
        final column = SchemaColumn(
          id: cId,
          name: rawName.isNotEmpty ? rawName : dbCol,
          dbColumnName: dbCol.isNotEmpty ? dbCol : rawName,
        );
        columnsInOrder.add(column);
        if (cId.isNotEmpty) columnsByIsn[cId] = column;
      }

      _tables[tObj] = SchemaTable(
        id: tObj,
        name: tName,
        // The JSON export carries no physical name; the logical name is the
        // best available approximation until DataSources.xml is loaded.
        physicalName: tName,
        dataSource: '',
        columnsByIsn: columnsByIsn,
        columnsInOrder: columnsInOrder,
        indexesById: const {},
      );
    }

    final progs = data['programs'] as List<dynamic>? ?? [];
    _programs
      ..clear()
      ..addAll(progs.map((x) => ProgramMetadata.fromJson(x)));

    _isLoaded = true;
  }

  Future<void> loadDataSourcesXmlFromDir(String dirPath) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    final candidates = [
      '$dirPath/DataSources.xml',
      '$dirPath/source/DataSources.xml',
      '${Directory(dirPath).parent.path}/DataSources.xml',
      '${Directory(dirPath).parent.path}/source/DataSources.xml',
    ];

    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) {
        await loadDataSourcesXml(file.path);
        break;
      }
    }
  }

  /// Parses DataSources.xml as an event stream. The file runs to ~19 MB, which
  /// is large enough that building a full document tree is wasteful.
  Future<void> loadDataSourcesXml(String xmlFilePath) async {
    if (_loadedDataSourcesPaths.contains(xmlFilePath)) return;
    final file = File(xmlFilePath);
    if (!await file.exists()) return;
    _loadedDataSourcesPaths.add(xmlFilePath);

    try {
      final xml = await file.readAsString();
      _consumeDataSourceEvents(parseEvents(xml));
    } catch (e) {
      // ignore: avoid_print
      print('Error parsing DataSources.xml: $e');
    }
  }

  /// Exposed so tests can feed XML directly without touching the filesystem.
  void parseDataSourcesString(String xmlString) {
    _consumeDataSourceEvents(parseEvents(xmlString));
  }

  void _consumeDataSourceEvents(Iterable<XmlEvent> events) {
    String? objId;
    String objName = '';
    String objPhysical = '';
    String objDataSource = '';
    bool objIsView = false;
    var columnsByIsn = <String, SchemaColumn>{};
    var columnsInOrder = <SchemaColumn>[];
    var indexesById = <String, SchemaIndex>{};

    String? columnId;
    String columnName = '';
    String columnDbName = '';
    String columnAttrObj = '';
    String columnPicture = '';
    int columnWhole = 0;
    int columnDec = 0;
    int columnSize = 0;

    String? indexId;
    String indexName = '';
    var indexSegments = <_RawSegment>[];
    bool indexUnique = false;
    int? segmentColumnPos;
    bool segmentDescending = false;

    // `<Column>` means different things under `<Columns>` and under
    // `<Segments>`, so the surrounding element has to be tracked.
    bool inColumns = false;
    bool inSegment = false;

    void flushTable() {
      if (objId == null) return;
      final resolvedIndexes = <String, SchemaIndex>{};
      indexesById.forEach((id, raw) => resolvedIndexes[id] = raw);
      _tables[objId!] = SchemaTable(
        id: objId!,
        name: objName,
        physicalName: objPhysical.isNotEmpty ? objPhysical : objName,
        dataSource: objDataSource,
        isView: objIsView,
        columnsByIsn: columnsByIsn,
        columnsInOrder: columnsInOrder,
        indexesById: resolvedIndexes,
      );
      objId = null;
    }

    for (final event in events) {
      if (event is XmlStartElementEvent) {
        switch (event.name) {
          case 'DataObject':
            flushTable();
            objId = _attr(event, 'id');
            objName = _attr(event, 'name') ?? '';
            objPhysical = _attr(event, 'PhysicalName') ?? '';
            objDataSource = _attr(event, 'data_source') ?? '';
            objIsView = false;
            columnsByIsn = <String, SchemaColumn>{};
            columnsInOrder = <SchemaColumn>[];
            indexesById = <String, SchemaIndex>{};
            break;

          case 'ObjectType':
            if (objId != null) objIsView = _attr(event, 'val') == 'V';
            break;

          case 'Columns':
            inColumns = true;
            break;

          case 'Segment':
            inSegment = true;
            segmentColumnPos = null;
            segmentDescending = false;
            break;

          case 'Column':
            if (inSegment) {
              segmentColumnPos = int.tryParse(_attr(event, 'val') ?? '');
            } else if (inColumns) {
              columnId = _attr(event, 'id');
              columnName = _attr(event, 'name') ?? '';
              columnDbName = '';
              columnAttrObj = '';
              columnPicture = '';
              columnWhole = 0;
              columnDec = 0;
              columnSize = 0;
              if (event.isSelfClosing) {
                _commitColumn(columnsByIsn, columnsInOrder, columnId, columnName,
                    columnDbName, 'NVARCHAR(255)');
                columnId = null;
              }
            }
            break;

          case 'DbColumnName':
            if (columnId != null) {
              columnDbName = (_attr(event, 'val') ?? '').trim();
            }
            break;

          case 'Model':
            if (columnId != null) columnAttrObj = _attr(event, 'attr_obj') ?? '';
            break;

          case 'Picture':
            if (columnId != null) columnPicture = _attr(event, 'valUnicode') ?? '';
            break;

          case '_Whole':
            if (columnId != null) {
              columnWhole = int.tryParse(_attr(event, 'val') ?? '') ?? 0;
            }
            break;

          case '_Dec':
            if (columnId != null) {
              columnDec = int.tryParse(_attr(event, 'val') ?? '') ?? 0;
            }
            break;

          case 'Size':
            if (columnId != null) {
              columnSize = int.tryParse(_attr(event, 'val') ?? '') ?? 0;
            }
            break;

          case 'Order':
            if (inSegment) segmentDescending = _attr(event, 'val') == 'D';
            break;

          case 'Mode':
            // Inside an Index, S marks a single/unique index.
            if (indexId != null && _attr(event, 'val') == 'S') {
              indexUnique = true;
            }
            break;

          case 'Primary':
            if (indexId != null && _attr(event, 'val') == 'Y') {
              indexUnique = true;
            }
            break;

          case 'Index':
            indexId = _attr(event, 'id');
            indexName = _attr(event, 'name') ?? '';
            indexSegments = <_RawSegment>[];
            indexUnique = false;
            break;
        }
      } else if (event is XmlEndElementEvent) {
        switch (event.name) {
          case 'DataObject':
            flushTable();
            break;

          case 'Columns':
            inColumns = false;
            break;

          case 'Column':
            if (!inSegment && inColumns && columnId != null) {
              _commitColumn(
                columnsByIsn,
                columnsInOrder,
                columnId,
                columnName,
                columnDbName,
                UnipaasTypeMapper.sqlType(
                  attrObj: columnAttrObj,
                  picture: columnPicture,
                  whole: columnWhole,
                  dec: columnDec,
                  size: columnSize,
                ),
              );
              columnId = null;
            }
            break;

          case 'Segment':
            if (segmentColumnPos != null) {
              indexSegments.add(
                _RawSegment(segmentColumnPos, segmentDescending),
              );
            }
            inSegment = false;
            break;

          case 'Index':
            if (indexId != null) {
              // Index segments address columns positionally; translate to ISN
              // now that the column order for this table is known.
              final segments = <IndexSegment>[];
              for (final raw in indexSegments) {
                if (raw.position >= 1 && raw.position <= columnsInOrder.length) {
                  segments.add(IndexSegment(
                    columnIsn: columnsInOrder[raw.position - 1].id,
                    descending: raw.descending,
                  ));
                }
              }
              indexesById[indexId] = SchemaIndex(
                id: indexId,
                name: indexName,
                segments: segments,
                unique: indexUnique,
              );
              indexId = null;
              indexUnique = false;
            }
            break;
        }
      }
    }

    flushTable();
  }

  void _commitColumn(
    Map<String, SchemaColumn> byIsn,
    List<SchemaColumn> inOrder,
    String? id,
    String name,
    String dbName,
    String sqlType,
  ) {
    if (id == null || id.isEmpty) return;
    final column = SchemaColumn(
      id: id,
      name: name.isNotEmpty ? name : dbName,
      dbColumnName: dbName.isNotEmpty ? dbName : name,
      sqlType: sqlType,
    );
    inOrder.add(column);
    byIsn[id] = column;
  }

  /// SQL type of a real column, used to declare parameters that stand in for
  /// values supplied by a parent task.
  String getColumnSqlType(String key, String colIsn) =>
      getTable(key)?.columnsByIsn[colIsn]?.sqlType ?? 'NVARCHAR(255)';

  static String? _attr(XmlStartElementEvent event, String name) {
    for (final a in event.attributes) {
      if (a.name == name) return a.value;
    }
    return null;
  }

  /// Data objects of external components, keyed "componentId:objectId".
  /// Their ids live in a separate namespace from the local ones, so they must
  /// never be resolved against [_tables].
  final Map<String, String> _componentTables = {};

  Future<void> loadComponentsXmlFromDir(String dirPath) async {
    for (final path in [
      '$dirPath/Comps.xml',
      '$dirPath/source/Comps.xml',
      '${Directory(dirPath).parent.path}/Comps.xml',
      '${Directory(dirPath).parent.path}/source/Comps.xml',
    ]) {
      final file = File(path);
      if (await file.exists()) {
        loadComponentsXml(await file.readAsString());
        return;
      }
    }
  }

  void loadComponentsXml(String xmlString) {
    String? componentId;
    String? objectId;
    var inDataObjects = false;

    for (final event in parseEvents(xmlString)) {
      if (event is XmlStartElementEvent) {
        switch (event.name) {
          case 'Component':
            componentId = _attr(event, 'id');
            break;
          case 'ComponentDataObjects':
            inDataObjects = true;
            break;
          case 'Object':
            objectId = null;
            break;
          case 'ItemIsn':
            // Tasks address a component's data object by its ItemIsn, not by
            // the `id` that also appears here.
            if (inDataObjects) objectId = _attr(event, 'val');
            break;
          case 'PublicName':
            if (inDataObjects && componentId != null && objectId != null) {
              final name = _attr(event, 'val') ?? '';
              if (name.isNotEmpty) {
                _componentTables['$componentId:$objectId'] = name;
              }
            }
            break;
        }
      } else if (event is XmlEndElementEvent && event.name == 'ComponentDataObjects') {
        inDataObjects = false;
      }
    }
  }

  /// Name of a data object owned by another component, or null when that
  /// component is not described by Comps.xml.
  String? getComponentTableName(String componentId, String tableObj) =>
      _componentTables['$componentId:$tableObj'];

  /// Data object ids are only unique within a component, so a table is
  /// addressed by a key that carries the component when it is not the local
  /// one: "13" locally, "3:13" for object 13 of component 3.
  static String tableKey(String componentId, String tableObj) {
    if (tableObj.isEmpty) return '';
    if (componentId.isEmpty || componentId == '-1') return tableObj;
    return '$componentId:$tableObj';
  }

  static bool isExternalTable(String key) => key.contains(':');

  static (String, String) _splitKey(String key) {
    final i = key.indexOf(':');
    return i == -1 ? ('-1', key) : (key.substring(0, i), key.substring(i + 1));
  }

  SchemaTable? getTable(String key) =>
      (key.isEmpty || isExternalTable(key)) ? null : _tables[key];

  String getTableName(String key) {
    if (key.isEmpty) return '';
    if (isExternalTable(key)) {
      final (comp, obj) = _splitKey(key);
      return getComponentTableName(comp, obj) ?? 'Component${comp}_Table$obj';
    }
    final table = _tables[key];
    if (table == null) return 'Table_$key';
    return table.physicalName.isNotEmpty ? table.physicalName : table.name;
  }

  String getDataSource(String key) => getTable(key)?.dataSource ?? '';

  /// False for Memory tables, XML databases and the like, which have no SQL
  /// representation. Unknown and external tables are assumed to be SQL.
  bool isSqlTable(String key) {
    final table = getTable(key);
    if (table == null) return true;
    if (table.dataSource.isEmpty) return true;
    return !_nonSqlDataSources.contains(table.dataSource);
  }

  /// [colIsn] is the column's `id` attribute, which is how tasks reference
  /// real columns. It is not a positional index.
  String getColumnName(String key, String colIsn) {
    if (key.isEmpty || colIsn.isEmpty) return 'UnknownColumn';
    final column = getTable(key)?.columnsByIsn[colIsn];
    return column?.dbColumnName ?? 'Col_$colIsn';
  }

  String getColumnAlias(String key, String colIsn, {required String fallback}) {
    if (key.isEmpty || colIsn.isEmpty) return fallback;
    final column = getTable(key)?.columnsByIsn[colIsn];
    if (column == null) return fallback;
    return column.name.isNotEmpty ? column.name : column.dbColumnName;
  }

  bool hasColumn(String key, String colIsn) =>
      getTable(key)?.columnsByIsn.containsKey(colIsn) ?? false;

  /// Whether reading [key] through [indexId] can match at most one row.
  bool isUniqueIndex(String key, String indexId) {
    if (indexId.isEmpty) return false;
    return getTable(key)?.indexesById[indexId]?.unique ?? false;
  }

  /// Columns of the index a task uses to read its main source, in index order.
  List<OrderByTerm> getIndexOrder(String key, String indexId) {
    final table = getTable(key);
    if (table == null || indexId.isEmpty) return const [];
    final index = table.indexesById[indexId];
    if (index == null) return const [];

    final tableName = getTableName(key);
    return [
      for (final segment in index.segments)
        OrderByTerm(
          tableName: tableName,
          colName: getColumnName(key, segment.columnIsn),
          descending: segment.descending,
        ),
    ];
  }

  ProgramMetadata? findProgramByIdOrFilename(String query) {
    for (final p in _programs) {
      if (p.id == query || p.filename == query || p.name == query) {
        return p;
      }
    }
    return null;
  }
}

class _RawSegment {
  final int position;
  final bool descending;
  _RawSegment(this.position, this.descending);
}
