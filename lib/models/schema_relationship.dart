/// A table-to-table link, still expressed in the UniPaaS object ids the XML
/// uses. Scanning produces these; resolving them against the data-source
/// repository turns them into a [SchemaRelationship].
class RawRelationship {
  /// Table key as produced by `SchemaService.tableKey`, so a data object owned
  /// by another component stays distinguishable from the local object of the
  /// same id.
  final String fromTableKey;
  final String fromColumnIsn;
  final String toTableKey;
  final String toColumnIsn;

  const RawRelationship({
    required this.fromTableKey,
    required this.fromColumnIsn,
    required this.toTableKey,
    required this.toColumnIsn,
  });

  /// Table keys already contain ':', so the flat form needs a separator that
  /// cannot occur inside an id.
  static const String fieldSeparator = '\u0001';

  /// Flat form used as a map key and to cross isolate boundaries.
  String encode() => [
        fromTableKey,
        fromColumnIsn,
        toTableKey,
        toColumnIsn,
      ].join(fieldSeparator);

  static RawRelationship decode(String encoded) {
    final parts = encoded.split(fieldSeparator);
    return RawRelationship(
      fromTableKey: parts[0],
      fromColumnIsn: parts[1],
      toTableKey: parts[2],
      toColumnIsn: parts[3],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RawRelationship &&
      other.fromTableKey == fromTableKey &&
      other.fromColumnIsn == fromColumnIsn &&
      other.toTableKey == toTableKey &&
      other.toColumnIsn == toColumnIsn;

  @override
  int get hashCode =>
      Object.hash(fromTableKey, fromColumnIsn, toTableKey, toColumnIsn);

  @override
  String toString() =>
      '$fromTableKey.$fromColumnIsn -> $toTableKey.$toColumnIsn';
}

/// A resolved link between two tables, together with every program whose logic
/// reads one through the other.
class SchemaRelationship {
  final String fromTable;
  final String fromColumn;
  final String toTable;
  final String toColumn;

  /// Program names, sorted, so the list reads the same on every scan.
  final List<String> programs;

  const SchemaRelationship({
    required this.fromTable,
    required this.fromColumn,
    required this.toTable,
    required this.toColumn,
    required this.programs,
  });

  bool get isSelfReference => fromTable == toTable;

  Map<String, dynamic> toJson() => {
        'fromTable': fromTable,
        'fromColumn': fromColumn,
        'toTable': toTable,
        'toColumn': toColumn,
        'programs': programs,
      };

  factory SchemaRelationship.fromJson(Map<String, dynamic> json) =>
      SchemaRelationship(
        fromTable: json['fromTable']?.toString() ?? '',
        fromColumn: json['fromColumn']?.toString() ?? '',
        toTable: json['toTable']?.toString() ?? '',
        toColumn: json['toColumn']?.toString() ?? '',
        programs: (json['programs'] as List<dynamic>? ?? const [])
            .map((p) => p.toString())
            .toList(),
      );

  @override
  String toString() => '$fromTable.$fromColumn -> $toTable.$toColumn';
}

/// The relationship set with the lookups the schema browser needs: what a
/// table points at, what points back at it, and what each program touches.
class SchemaGraph {
  final List<SchemaRelationship> relationships;

  final Map<String, List<SchemaRelationship>> _outgoing;
  final Map<String, List<SchemaRelationship>> _incoming;
  final Map<String, List<SchemaRelationship>> _byProgram;

  /// Program names in alphabetical order.
  final List<String> programs;

  /// Program name to the XML file it was read from, so the browser can hand a
  /// program straight to the SQL generator. Two programs sharing a description
  /// collapse to whichever was scanned first.
  final Map<String, String> programFiles;

  SchemaGraph._(
    this.relationships,
    this._outgoing,
    this._incoming,
    this._byProgram,
    this.programs,
    this.programFiles,
  );

  static final SchemaGraph empty = SchemaGraph.from(const []);

  factory SchemaGraph.from(
    List<SchemaRelationship> relationships, {
    Map<String, String> programFiles = const {},
  }) {
    final outgoing = <String, List<SchemaRelationship>>{};
    final incoming = <String, List<SchemaRelationship>>{};
    final byProgram = <String, List<SchemaRelationship>>{};

    for (final rel in relationships) {
      outgoing.putIfAbsent(rel.fromTable, () => []).add(rel);
      incoming.putIfAbsent(rel.toTable, () => []).add(rel);
      for (final program in rel.programs) {
        byProgram.putIfAbsent(program, () => []).add(rel);
      }
    }

    final programNames = byProgram.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return SchemaGraph._(
      List.unmodifiable(relationships),
      outgoing,
      incoming,
      byProgram,
      List.unmodifiable(programNames),
      Map.unmodifiable(programFiles),
    );
  }

  /// The XML file a program was read from, when the scan recorded one.
  String? fileForProgram(String program) => programFiles[program];

  bool get isEmpty => relationships.isEmpty;

  List<SchemaRelationship> outgoingFor(String table) =>
      _outgoing[table] ?? const [];

  List<SchemaRelationship> incomingFor(String table) =>
      _incoming[table] ?? const [];

  List<SchemaRelationship> forProgram(String program) =>
      _byProgram[program] ?? const [];

  /// How many links a table takes part in, counting both directions. Matches
  /// the count the card and list rows show.
  int degreeOf(String table) =>
      outgoingFor(table).length + incomingFor(table).length;
}
