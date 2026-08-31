import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sql_converter/models/unipaas_models.dart';
import 'package:flutter_sql_converter/services/program_cache_service.dart';

void main() {
  group('ProgramCacheService', () {
    late Directory tempDir;
    late String cacheFilePath;
    late ProgramCacheService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('program_cache_test_');
      cacheFilePath = '${tempDir.path}/test_cache.json';
      service = ProgramCacheService(cacheFilePath: cacheFilePath);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('computeFingerprint returns empty string for nonexistent directory', () async {
      final fingerprint = await service.computeFingerprint('${tempDir.path}/nonexistent');
      expect(fingerprint, isEmpty);
    });

    test('computeFingerprint returns empty string for directory without xml files', () async {
      final file = File('${tempDir.path}/test.txt');
      await file.writeAsString('hello');
      final fingerprint = await service.computeFingerprint(tempDir.path);
      expect(fingerprint, isEmpty);
    });

    test('computeFingerprint computes stable fingerprint and detects file additions/modifications', () async {
      final xml1 = File('${tempDir.path}/Prg_1.xml');
      await xml1.writeAsString('<Task><Header Description="Test 1"/></Task>');

      final fp1 = await service.computeFingerprint(tempDir.path);
      expect(fp1, isNotEmpty);
      expect(fp1, startsWith('v1:1:'));

      // Same files -> same fingerprint
      final fp2 = await service.computeFingerprint(tempDir.path);
      expect(fp2, equals(fp1));

      // Add second file -> fingerprint changes
      final xml2 = File('${tempDir.path}/Prg_2.xml');
      await xml2.writeAsString('<Task><Header Description="Test 2"/></Task>');

      final fp3 = await service.computeFingerprint(tempDir.path);
      expect(fp3, isNot(equals(fp1)));
      expect(fp3, startsWith('v1:2:'));
    });

    test('readCache and writeCache round-trip program metadata accurately', () async {
      final programs = [
        ProgramMetadata(
          id: '1',
          filename: 'Prg_1.xml',
          name: 'First Program',
          parameters: [
            ProgramParameter(
              fieldId: '1',
              colId: '1',
              name: 'p_UserID',
              type: 'ALPHA',
              isParameter: true,
              sourceNote: 'from caller',
              currentValue: '123',
            ),
          ],
          hasTables: true,
        ),
        ProgramMetadata(
          id: '2',
          filename: 'Prg_2.xml',
          name: 'Second Program',
          parameters: [],
          hasTables: false,
        ),
      ];

      const fingerprint = 'v1:2:1234:5678';
      await service.writeCache(tempDir.path, fingerprint, programs);

      final cached = await service.readCache(tempDir.path);
      expect(cached, isNotNull);
      expect(cached!.directory, equals(tempDir.path));
      expect(cached.fingerprint, equals(fingerprint));
      expect(cached.programs.length, equals(2));

      final p1 = cached.programs[0];
      expect(p1.id, equals('1'));
      expect(p1.filename, equals('Prg_1.xml'));
      expect(p1.name, equals('First Program'));
      expect(p1.hasTables, isTrue);
      expect(p1.parameters.length, equals(1));
      expect(p1.parameters[0].name, equals('p_UserID'));
      expect(p1.parameters[0].sourceNote, equals('from caller'));
      expect(p1.parameters[0].currentValue, equals('123'));

      final p2 = cached.programs[1];
      expect(p2.id, equals('2'));
      expect(p2.filename, equals('Prg_2.xml'));
      expect(p2.hasTables, isFalse);
    });

    test('readCache returns null if cache file does not exist or directory does not match', () async {
      expect(await service.readCache(tempDir.path), isNull);

      final programs = [
        ProgramMetadata(id: '1', filename: 'Prg_1.xml', name: 'P1', parameters: []),
      ];
      await service.writeCache(tempDir.path, 'fp1', programs);

      // Querying different directory should return null
      expect(await service.readCache('/some/other/dir'), isNull);
    });

    test('hasChanges detects differences between directory state and cached fingerprint', () async {
      final xml1 = File('${tempDir.path}/Prg_1.xml');
      await xml1.writeAsString('<Task><Header/></Task>');

      final fp = await service.computeFingerprint(tempDir.path);
      expect(await service.hasChanges(tempDir.path, fp), isFalse);

      // Modify the file
      await Future.delayed(const Duration(milliseconds: 50));
      await xml1.writeAsString('<Task><Header Description="Updated"/></Task>');

      expect(await service.hasChanges(tempDir.path, fp), isTrue);
    });

    test('clearCache deletes cache file', () async {
      final programs = [
        ProgramMetadata(id: '1', filename: 'Prg_1.xml', name: 'P1', parameters: []),
      ];
      await service.writeCache(tempDir.path, 'fp1', programs);
      expect(File(cacheFilePath).existsSync(), isTrue);

      await service.clearCache();
      expect(File(cacheFilePath).existsSync(), isFalse);
    });
  });
}
