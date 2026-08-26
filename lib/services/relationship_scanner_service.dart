import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:xml/xml.dart';

import '../models/schema_relationship.dart';
import 'schema_service.dart';

/// What one program file contributed to the relationship set.
class ProgramRelationshipScan {
  /// The task header's description, or the filename when it has none.
  final String programName;
  final Set<RawRelationship> relationships;

  const ProgramRelationshipScan(this.programName, this.relationships);
}

/// Outcome of sweeping a whole source folder.
class RelationshipScanResult {
  final SchemaGraph graph;
  final int filesScanned;
  final int filesFailed;
  final Duration duration;
  final bool fromCache;

  const RelationshipScanResult({
    required this.graph,
    required this.filesScanned,
    required this.filesFailed,
    required this.duration,
    required this.fromCache,
  });
}

/// Recovers foreign-key-like links from UniPaaS program logic.
///
/// A task's dataview reads its main source and then links to other tables. When
/// a linked table's column carries a `Locate` whose range is exactly one
/// earlier dataview field (`{0,N}`), that pairing is the application's way of
/// saying "match this row by that value" — which is a foreign key in all but
/// name. Everything here is derived from that single signal.
class RelationshipScanner {
  /// A `Locate` bound to nothing but a bare field reference. Anything with
  /// arithmetic or literals around it is a filter, not a key match.
  static final RegExp _bareFieldReference = RegExp(r'^\{0,(\d+)\}$');

  /// Reads one program's XML. Pure, so it runs unchanged on a worker isolate
  /// and in tests.
  static ProgramRelationshipScan scanProgram(
    String xml, {
    required String fallbackName,
  }) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(xml);
    } on XmlException {
      return ProgramRelationshipScan(fallbackName, const {});
    }

    final tasks = document.findAllElements('Task').toList();

    var programName = fallbackName;
    if (tasks.isNotEmpty) {
      // Some descriptions carry stray leading whitespace, which would sort the
      // program to the top of an otherwise alphabetical list.
      final description = tasks.first
          .findElements('Header')
          .firstOrNull
          ?.getAttribute('Description')
          ?.trim();
      if (description != null && description.isNotEmpty) {
        programName = description;
      }
    }

    // Subtasks each have their own main source and link stack, so every task in
    // the file is walked independently.
    final found = <RawRelationship>{};
    for (final task in tasks) {
      _scanTask(task, found);
    }

    return ProgramRelationshipScan(programName, found);
  }

  static void _scanTask(XmlElement task, Set<RawRelationship> out) {
    final mainTableKey = _mainSourceKey(task);
    final expressions = _expressionsByPosition(task);

    // Which table and column each dataview field reads. It has to outlive the
    // logic unit that declared the field, because a later unit's Locate can
    // still point back at it.
    final fieldSources = <String, RawColumnRef>{};

    var currentTableKey = mainTableKey;
    final linkStack = <String>[];

    final units = task
        .findElements('TaskLogic')
        .expand((logic) => logic.findElements('LogicUnit'));

    for (final unit in units) {
      final lines = unit.findElements('LogicLines').firstOrNull;
      if (lines == null) continue;

      for (final line in lines.childElements) {
        if (line.name.local != 'LogicLine') continue;
        final operation = line.childElements.firstOrNull;
        if (operation == null) continue;

        switch (operation.name.local) {
          case 'DATAVIEW_SRC':
            currentTableKey = mainTableKey;
            linkStack.clear();

          case 'LNK':
            linkStack.add(currentTableKey);
            final linked = SchemaService.tableKeyOfDbNode(
              operation.findElements('DB').firstOrNull,
            );
            // A link with no readable object leaves the context alone rather
            // than blanking it, so the selects that follow stay attributable.
            if (linked.isNotEmpty) currentTableKey = linked;

          case 'END_LINK':
            currentTableKey =
                linkStack.isNotEmpty ? linkStack.removeLast() : mainTableKey;

          case 'Select':
            _readSelect(
              operation,
              currentTableKey: currentTableKey,
              expressions: expressions,
              fieldSources: fieldSources,
              out: out,
            );
        }
      }
    }
  }

  static void _readSelect(
    XmlElement select, {
    required String currentTableKey,
    required Map<String, String> expressions,
    required Map<String, RawColumnRef> fieldSources,
    required Set<RawRelationship> out,
  }) {
    final fieldId = select.getAttribute('FieldID') ?? '';
    final columnIsn =
        select.findElements('Column').firstOrNull?.getAttribute('val') ?? '';
    final fieldType =
        select.findElements('Type').firstOrNull?.getAttribute('val') ?? 'U';
    final isParameter =
        select.findElements('IsParameter').firstOrNull?.getAttribute('val') ??
            'N';

    // Only a real column of the current table can be one end of a key match;
    // virtuals and parameters carry no column of their own.
    final isRealColumn = fieldType == 'R' && isParameter != 'Y';

    if (isRealColumn &&
        fieldId.isNotEmpty &&
        columnIsn.isNotEmpty &&
        currentTableKey.isNotEmpty) {
      fieldSources[fieldId] =
          RawColumnRef(tableKey: currentTableKey, columnIsn: columnIsn);
    }

    final locate = select.findElements('Locate').firstOrNull;
    if (locate == null || !isRealColumn) return;

    final max = locate.getAttribute('MAX') ?? '';
    final min = locate.getAttribute('MIN') ?? '';
    final expressionId = max.isNotEmpty ? max : min;
    if (expressionId.isEmpty) return;

    final syntax = expressions[expressionId];
    if (syntax == null) return;

    final match = _bareFieldReference.firstMatch(syntax);
    if (match == null) return;

    final source = fieldSources[match.group(1)!];
    if (source == null) return;

    out.add(RawRelationship(
      fromTableKey: source.tableKey,
      fromColumnIsn: source.columnIsn,
      toTableKey: currentTableKey,
      toColumnIsn: columnIsn,
    ));
  }

  /// The task's own main source: `Information/DB`, or the resource block when
  /// the task states its source there instead.
  static String _mainSourceKey(XmlElement task) {
    final information = _firstOnPath(task, const ['Information', 'DB']);
    final fromInformation = SchemaService.tableKeyOfDbNode(information);
    if (fromInformation.isNotEmpty) return fromInformation;
    return SchemaService.tableKeyOfDbNode(_firstOnPath(task, const ['Resource', 'DB']));
  }

  /// `Locate` and `Range` address an expression by its 1-based position in the
  /// `Expressions` block, not by the `id` attribute, which is not in order.
  static Map<String, String> _expressionsByPosition(XmlElement task) {
    final block = task.findElements('Expressions').firstOrNull;
    if (block == null) return const {};

    final byPosition = <String, String>{};
    var position = 1;
    for (final expression in block.findElements('Expression')) {
      final syntax =
          expression.findElements('ExpSyntax').firstOrNull?.getAttribute('val');
      if (syntax != null) byPosition['$position'] = syntax;
      position++;
    }
    return byPosition;
  }

  static XmlElement? _firstOnPath(XmlElement root, List<String> path) {
    var level = [root];
    for (final name in path) {
      final next = [
        for (final element in level)
          ...element.childElements.where((c) => c.name.local == name),
      ];
      if (next.isEmpty) return null;
      level = next;
    }
    return level.first;
  }

  /// Turns scanned object ids into table and column names. A link whose ends
  /// are not both in the data-source repository is dropped: an unresolvable id
  /// would otherwise show up as a relationship between invented tables.
  static SchemaGraph resolve(
    Map<String, Set<String>> rawRelationships,
    SchemaService schema, {
    Map<String, String> programFiles = const {},
  }) {
    final resolved = <SchemaRelationship>[];

    rawRelationships.forEach((encoded, programs) {
      final raw = RawRelationship.decode(encoded);

      final fromTable = schema.getTable(raw.fromTableKey);
      final toTable = schema.getTable(raw.toTableKey);
      if (fromTable == null || toTable == null) return;

      final fromColumn = fromTable.columnsByIsn[raw.fromColumnIsn];
      final toColumn = toTable.columnsByIsn[raw.toColumnIsn];
      if (fromColumn == null || toColumn == null) return;

      final fromTableName = _displayName(fromTable.name, fromTable.physicalName);
      final toTableName = _displayName(toTable.name, toTable.physicalName);
      if (fromTableName.isEmpty || toTableName.isEmpty) return;

      resolved.add(SchemaRelationship(
        fromTable: fromTableName,
        fromColumn: _displayName(fromColumn.name, fromColumn.dbColumnName),
        toTable: toTableName,
        toColumn: _displayName(toColumn.name, toColumn.dbColumnName),
        programs: programs.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
      ));
    });

    resolved.sort((a, b) {
      final byFrom = a.fromTable.toLowerCase().compareTo(b.fromTable.toLowerCase());
      if (byFrom != 0) return byFrom;
      final byColumn =
          a.fromColumn.toLowerCase().compareTo(b.fromColumn.toLowerCase());
      if (byColumn != 0) return byColumn;
      return a.toTable.toLowerCase().compareTo(b.toTable.toLowerCase());
    });

    return SchemaGraph.from(resolved, programFiles: programFiles);
  }

  static String _displayName(String preferred, String fallback) =>
      preferred.isNotEmpty ? preferred : fallback;
}

/// One end of a link, in the ids the XML uses.
class RawColumnRef {
  final String tableKey;
  final String columnIsn;

  const RawColumnRef({required this.tableKey, required this.columnIsn});
}

/// Sweeps a folder of program files, on worker isolates, with a disk cache so
/// only the first run of a given export pays for the scan.
class RelationshipScannerService {
  static final RegExp _programFile = RegExp(r'Prg_\d+\.xml$', caseSensitive: false);

  /// A full pass over ~8,000 files is a lot of XML; spreading it over a few
  /// isolates keeps the UI responsive and the wall time reasonable.
  static const int _workerCount = 6;

  /// Bump whenever a change to the scan would produce different output for the
  /// same files, so an existing cache is discarded rather than served forever.
  static const int _cacheFormatVersion = 2;

  /// Where the scan result is remembered between launches. Overridable so a
  /// test never writes over the developer's own cache.
  final String cacheFilePath;

  RelationshipScannerService({String? cacheFilePath})
      : cacheFilePath = cacheFilePath ?? defaultCacheFilePath;

  static String get defaultCacheFilePath {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return '$home/.flutter_sql_converter_relationships.json';
  }

  Future<RelationshipScanResult> scanDirectory(
    String directory,
    SchemaService schema, {
    void Function(int done, int total)? onProgress,
    bool useCache = true,
  }) async {
    final stopwatch = Stopwatch()..start();

    final dir = Directory(directory);
    if (!await dir.exists()) {
      return RelationshipScanResult(
        graph: SchemaGraph.empty,
        filesScanned: 0,
        filesFailed: 0,
        duration: stopwatch.elapsed,
        fromCache: false,
      );
    }

    final entries = await dir
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.xml'))
        .cast<File>()
        .toList();

    final fingerprint = await _fingerprint(entries);
    if (useCache) {
      final cached = await _readCache(directory, fingerprint);
      if (cached != null) {
        return RelationshipScanResult(
          graph: cached,
          filesScanned: entries.where((f) => _programFile.hasMatch(f.path)).length,
          filesFailed: 0,
          duration: stopwatch.elapsed,
          fromCache: true,
        );
      }
    }

    final paths = [
      for (final file in entries)
        if (_programFile.hasMatch(file.path)) file.path,
    ]..sort();

    if (paths.isEmpty) {
      return RelationshipScanResult(
        graph: SchemaGraph.empty,
        filesScanned: 0,
        filesFailed: 0,
        duration: stopwatch.elapsed,
        fromCache: false,
      );
    }

    final raw = <String, Set<String>>{};
    final programFiles = <String, String>{};
    var failed = 0;
    var done = 0;

    final chunks = _chunk(paths, _workerCount);
    final port = ReceivePort();
    var outstanding = chunks.length;
    final finished = Completer<void>();

    port.listen((message) {
      if (message is List && message.isNotEmpty && message[0] == 'progress') {
        done += message[1] as int;
        onProgress?.call(done, paths.length);
        return;
      }

      if (message is List && message.isNotEmpty && message[0] == 'done') {
        final partial = message[1] as Map;
        partial.forEach((key, programs) {
          raw
              .putIfAbsent(key as String, () => <String>{})
              .addAll((programs as List).cast<String>());
        });
        (message[2] as Map).forEach((name, file) {
          programFiles.putIfAbsent(name as String, () => file as String);
        });
        failed += message[3] as int;
      } else {
        // An uncaught error in a worker arrives here as [error, stack]; the
        // chunk is lost but the rest of the scan still completes.
        failed += 1;
      }

      outstanding -= 1;
      if (outstanding == 0 && !finished.isCompleted) {
        port.close();
        finished.complete();
      }
    });

    try {
      for (final chunk in chunks) {
        await Isolate.spawn(
          _scanWorker,
          [port.sendPort, chunk],
          onError: port.sendPort,
          errorsAreFatal: true,
        );
      }

      await finished.future;
    } finally {
      // If a spawn throws part-way through, the workers already running would
      // otherwise keep the port — and this scan — alive forever.
      port.close();
    }

    final graph =
        RelationshipScanner.resolve(raw, schema, programFiles: programFiles);
    await _writeCache(directory, fingerprint, graph);

    return RelationshipScanResult(
      graph: graph,
      filesScanned: paths.length,
      filesFailed: failed,
      duration: stopwatch.elapsed,
      fromCache: false,
    );
  }

  /// Runs on a worker isolate: scans its slice and reports progress as it goes.
  static void _scanWorker(List<Object?> request) {
    final send = request[0] as SendPort;
    final paths = (request[1] as List).cast<String>();

    final raw = <String, List<String>>{};
    final programFiles = <String, String>{};
    var failed = 0;
    var sinceTick = 0;

    for (final path in paths) {
      try {
        final file = File(path);
        final filename = file.uri.pathSegments.last;
        final scan = RelationshipScanner.scanProgram(
          file.readAsStringSync(),
          fallbackName: filename,
        );
        if (scan.relationships.isNotEmpty) {
          programFiles.putIfAbsent(scan.programName, () => filename);
          for (final relationship in scan.relationships) {
            final programs =
                raw.putIfAbsent(relationship.encode(), () => <String>[]);
            if (!programs.contains(scan.programName)) {
              programs.add(scan.programName);
            }
          }
        }
      } catch (_) {
        failed += 1;
      }

      sinceTick += 1;
      if (sinceTick == 50) {
        send.send(['progress', sinceTick]);
        sinceTick = 0;
      }
    }

    if (sinceTick > 0) send.send(['progress', sinceTick]);
    send.send(['done', raw, programFiles, failed]);
  }

  static List<List<String>> _chunk(List<String> paths, int count) {
    final workers = count.clamp(1, paths.length);
    final chunks = List.generate(workers, (_) => <String>[]);
    for (var i = 0; i < paths.length; i++) {
      chunks[i % workers].add(paths[i]);
    }
    return chunks;
  }

  /// Cheap stand-in for "the export has not changed": how many XML files there
  /// are, their total size, and the newest modification time. Covers
  /// DataSources.xml too, so renamed columns invalidate the cache.
  Future<String> _fingerprint(List<File> files) async {
    var totalSize = 0;
    var newest = 0;
    for (final file in files) {
      try {
        final stat = await file.stat();
        totalSize += stat.size;
        final modified = stat.modified.millisecondsSinceEpoch;
        if (modified > newest) newest = modified;
      } catch (_) {}
    }
    return 'v$_cacheFormatVersion:${files.length}:$totalSize:$newest';
  }

  Future<SchemaGraph?> _readCache(String directory, String fingerprint) async {
    try {
      final file = File(cacheFilePath);
      if (!await file.exists()) return null;
      final data = json.decode(await file.readAsString()) as Map<String, dynamic>;
      if (data['directory'] != directory) return null;
      if (data['fingerprint'] != fingerprint) return null;

      final relationships = (data['relationships'] as List<dynamic>? ?? [])
          .map((r) => SchemaRelationship.fromJson(r as Map<String, dynamic>))
          .toList();
      final programFiles = (data['programFiles'] as Map<String, dynamic>? ?? {})
          .map((name, file) => MapEntry(name, file.toString()));
      return SchemaGraph.from(relationships, programFiles: programFiles);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(
    String directory,
    String fingerprint,
    SchemaGraph graph,
  ) async {
    try {
      await File(cacheFilePath).writeAsString(
        json.encode({
          'directory': directory,
          'fingerprint': fingerprint,
          'scannedAt': DateTime.now().toIso8601String(),
          'relationships': [for (final r in graph.relationships) r.toJson()],
          'programFiles': graph.programFiles,
        }),
        flush: true,
      );
    } catch (_) {
      // A missing cache only costs time on the next launch.
    }
  }
}
