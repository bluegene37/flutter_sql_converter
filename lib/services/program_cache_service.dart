import 'dart:convert';
import 'dart:io';

import '../models/unipaas_models.dart';

/// Cached program scan results and metadata for a specific directory.
class ProgramCacheData {
  final String directory;
  final String fingerprint;
  final DateTime scannedAt;
  final List<ProgramMetadata> programs;

  const ProgramCacheData({
    required this.directory,
    required this.fingerprint,
    required this.scannedAt,
    required this.programs,
  });
}

/// Manages persistent disk caching of scanned UniPaaS XML programs and
/// provides ultra-fast fingerprint-based change detection.
class ProgramCacheService {
  static const int _cacheFormatVersion = 1;

  final String cacheFilePath;

  ProgramCacheService({String? cacheFilePath})
      : cacheFilePath = cacheFilePath ?? defaultCacheFilePath;

  static String get defaultCacheFilePath {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return '$home/.flutter_sql_converter_programs_cache.json';
  }

  /// Quickly computes a lightweight fingerprint of all XML files in [directory]
  /// using file counts, total file sizes, and newest modification times.
  /// This takes ~20-40ms even for thousands of files and does not read file contents.
  Future<String> computeFingerprint(String directory) async {
    final dir = Directory(directory);
    if (!await dir.exists()) return '';

    try {
      final entries = await dir
          .list()
          .where((e) => e is File && e.path.toLowerCase().endsWith('.xml'))
          .cast<File>()
          .toList();

      if (entries.isEmpty) return '';

      var totalSize = 0;
      var newest = 0;

      for (final file in entries) {
        try {
          final stat = await file.stat();
          totalSize += stat.size;
          final modified = stat.modified.millisecondsSinceEpoch;
          if (modified > newest) newest = modified;
        } catch (_) {}
      }

      // Also check ProgramHeaders.xml in parent if present
      final parentDir = dir.parent;
      final parentHeaders = File('${parentDir.path}/ProgramHeaders.xml');
      if (await parentHeaders.exists()) {
        try {
          final stat = await parentHeaders.stat();
          totalSize += stat.size;
          final modified = stat.modified.millisecondsSinceEpoch;
          if (modified > newest) newest = modified;
        } catch (_) {}
      }

      return 'v$_cacheFormatVersion:${entries.length}:$totalSize:$newest';
    } catch (_) {
      return '';
    }
  }

  /// Reads the cached programs for [directory] if available.
  Future<ProgramCacheData?> readCache(String directory) async {
    try {
      final file = File(cacheFilePath);
      if (!await file.exists()) return null;

      final jsonStr = await file.readAsString();
      if (jsonStr.trim().isEmpty) return null;

      final data = json.decode(jsonStr) as Map<String, dynamic>;
      if (data['directory'] != directory) return null;

      final fingerprint = data['fingerprint']?.toString() ?? '';
      final scannedAtStr = data['scannedAt']?.toString();
      final scannedAt = scannedAtStr != null
          ? DateTime.tryParse(scannedAtStr) ?? DateTime.now()
          : DateTime.now();

      final progsRaw = data['programs'] as List<dynamic>? ?? [];
      final programs = progsRaw
          .map((p) => ProgramMetadata.fromJson(p as Map<String, dynamic>))
          .toList();

      if (programs.isEmpty) return null;

      return ProgramCacheData(
        directory: directory,
        fingerprint: fingerprint,
        scannedAt: scannedAt,
        programs: programs,
      );
    } catch (_) {
      return null;
    }
  }

  /// Writes [programs] and directory [fingerprint] to disk cache.
  Future<void> writeCache(
    String directory,
    String fingerprint,
    List<ProgramMetadata> programs,
  ) async {
    if (directory.trim().isEmpty || programs.isEmpty) return;
    try {
      final file = File(cacheFilePath);
      final data = {
        'directory': directory,
        'fingerprint': fingerprint,
        'scannedAt': DateTime.now().toIso8601String(),
        'programs': programs.map((p) => p.toJson()).toList(),
      };
      await file.writeAsString(json.encode(data), flush: true);
    } catch (e) {
      // Non-fatal: missing cache only means scanning again next launch
      // ignore: avoid_print
      print('Warning: could not write program cache: $e');
    }
  }

  /// Checks whether the files in [directory] have changed compared to [cachedFingerprint].
  Future<bool> hasChanges(String directory, String cachedFingerprint) async {
    if (directory.trim().isEmpty) return false;
    final currentFingerprint = await computeFingerprint(directory);
    if (currentFingerprint.isEmpty) return false;
    return currentFingerprint != cachedFingerprint;
  }

  /// Deletes the cache file.
  Future<void> clearCache() async {
    try {
      final file = File(cacheFilePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
