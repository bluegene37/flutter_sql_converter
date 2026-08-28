import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_sql_converter/services/update/update_info.dart';
import 'package:flutter_sql_converter/services/update/update_service.dart';

Map<String, dynamic> release(String tag) => {
      'tag_name': tag,
      'html_url':
          'https://github.com/bluegene37/flutter_sql_converter/releases/tag/$tag',
      'assets': [
        {
          'name': 'MagicSoftSQL-x86_64-Installer.exe',
          'browser_download_url': 'https://example.com/installer.exe',
          'size': 10,
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int fetchCalls;

  UpdateService service({
    String latestTag = 'v1.1.0',
    String currentVersion = '1.0.0',
    DateTime? now,
    Object? fetchError,
  }) {
    return UpdateService(
      currentVersion: currentVersion,
      platform: UpdatePlatform.windows,
      now: () => now ?? DateTime(2026, 8, 28, 12),
      fetchRelease: (_) async {
        fetchCalls++;
        if (fetchError != null) throw fetchError;
        return release(latestTag);
      },
    );
  }

  setUp(() {
    fetchCalls = 0;
    SharedPreferences.setMockInitialValues({});
  });

  test('feed url points at this repo\'s latest release', () {
    expect(
      UpdateService.latestReleaseUrl.toString(),
      'https://api.github.com/repos/bluegene37/flutter_sql_converter/releases/latest',
    );
  });

  group('checkForUpdate', () {
    test('reports available when a newer release exists', () async {
      final result = await service().checkForUpdate();
      expect(result.status, UpdateStatus.available);
      expect(result.info!.version.toString(), '1.1.0');
      expect(fetchCalls, 1);
    });

    test('reports upToDate when latest equals current', () async {
      final result = await service(latestTag: 'v1.0.0').checkForUpdate();
      expect(result.status, UpdateStatus.upToDate);
    });

    test('reports upToDate when latest is older than current', () async {
      final result = await service(
        latestTag: 'v1.0.0',
        currentVersion: '2.0.0',
      ).checkForUpdate();
      expect(result.status, UpdateStatus.upToDate);
    });

    test('throttles network calls within the check interval', () async {
      await service().checkForUpdate();
      expect(fetchCalls, 1);

      // Second check 1 hour later: no network call, but the cached release
      // still surfaces the available update (survives an app restart).
      final result = await service(
        now: DateTime(2026, 8, 28, 13),
      ).checkForUpdate();
      expect(fetchCalls, 1);
      expect(result.status, UpdateStatus.available);
      expect(result.info!.version.toString(), '1.1.0');
    });

    test('checks the network again after the interval elapses', () async {
      await service().checkForUpdate();
      await service(now: DateTime(2026, 8, 29, 13)).checkForUpdate();
      expect(fetchCalls, 2);
    });

    test('force bypasses the throttle', () async {
      await service().checkForUpdate();
      await service().checkForUpdate(force: true);
      expect(fetchCalls, 2);
    });

    test('failed fetch does not overwrite the cached release', () async {
      await service().checkForUpdate();
      await service(fetchError: Exception('offline'))
          .checkForUpdate(force: true);

      // Back inside the throttle window: the cache from the first, good
      // fetch must still be there.
      final result = await service(
        now: DateTime(2026, 8, 28, 13),
      ).checkForUpdate();
      expect(result.status, UpdateStatus.available);
    });

    test('a skipped version is reported as skipped, not available', () async {
      final s = service();
      final first = await s.checkForUpdate();
      await s.skipVersion(first.info!.version);

      final result = await s.checkForUpdate(force: true);
      expect(result.status, UpdateStatus.skipped);
    });

    test('a release newer than the skipped one is available again', () async {
      final s = service();
      final first = await s.checkForUpdate();
      await s.skipVersion(first.info!.version);

      final result = await service(
        latestTag: 'v1.2.0',
      ).checkForUpdate(force: true);
      expect(result.status, UpdateStatus.available);
    });

    test('ignoreSkipped surfaces a skipped version as available again',
        () async {
      // A manual "Check for updates" should always show what exists.
      final s = service();
      final first = await s.checkForUpdate();
      await s.skipVersion(first.info!.version);

      final result = await s.checkForUpdate(force: true, ignoreSkipped: true);
      expect(result.status, UpdateStatus.available);
    });

    test('network failure yields failed result without throwing', () async {
      final result = await service(
        fetchError: const SocketException('offline'),
      ).checkForUpdate();
      expect(result.status, UpdateStatus.failed);
      expect(result.error, isA<SocketException>());
    });

    test('unparseable release tag yields failed result', () async {
      final result = await service(latestTag: 'nightly').checkForUpdate();
      expect(result.status, UpdateStatus.failed);
    });
  });

  group('downloadAsset', () {
    setUpAll(() {
      // The flutter_test binding replaces HttpClient with a stub that always
      // returns 400. These tests exercise the real client against a local
      // loopback server, so restore real networking for this group.
      HttpOverrides.global = null;
    });

    test('downloads bytes to a file, reports progress, verifies size',
        () async {
      final bytes = List<int>.generate(1024, (i) => i % 256);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response
          ..headers.contentType = ContentType.binary
          ..add(bytes);
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final dir = Directory.systemTemp.createTempSync('upd_test_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final asset = UpdateAsset(
        name: 'installer.exe',
        downloadUrl: 'http://127.0.0.1:${server.port}/installer.exe',
        size: bytes.length,
      );

      final progress = <(int, int)>[];
      final file = await UpdateService.downloadAsset(
        asset,
        dir: dir,
        onProgress: (received, total) => progress.add((received, total)),
      );
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), bytes.length);
      expect(progress, isNotEmpty);
      expect(progress.last.$1, bytes.length);
      expect(progress.last.$2, bytes.length);
    });

    test('deletes the partial file and throws on a size mismatch', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response.add([1, 2, 3]);
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final dir = Directory.systemTemp.createTempSync('upd_test_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final asset = UpdateAsset(
        name: 'installer.exe',
        downloadUrl: 'http://127.0.0.1:${server.port}/installer.exe',
        size: 999,
      );

      await expectLater(
        () => UpdateService.downloadAsset(asset, dir: dir),
        throwsA(isA<StateError>()),
      );
      expect(File('${dir.path}/installer.exe').existsSync(), isFalse);
    });
  });

  group('windows install script', () {
    test('quotes paths, installs silently, relaunches, self-deletes', () {
      final script = UpdateService.buildWindowsInstallScript(
        installerPath: r'C:\Users\Jo Doe\AppData\Local\Temp\inst.exe',
        appExePath: r'C:\Program Files\MagicSoftSQL\magicsoftsql.exe',
      );
      expect(
        script,
        contains('"C:\\Users\\Jo Doe\\AppData\\Local\\Temp\\inst.exe"'),
      );
      expect(script, contains('/SILENT'));
      expect(script, contains('/CLOSEAPPLICATIONS'));
      expect(script, contains('/NORESTART'));
      expect(script, contains('del "%~f0"'));
      expect(script.split('\n').every((l) => l.isEmpty || l.endsWith('\r')),
          isTrue,
          reason: 'batch scripts need CRLF line endings');
      // Relaunch line must come after the installer invocation.
      final installIdx = script.indexOf('inst.exe');
      final relaunchIdx = script.indexOf('magicsoftsql.exe');
      expect(relaunchIdx, greaterThan(installIdx));
    });
  });

  group('openUrlCommand', () {
    test('uses the platform launcher for the release page', () {
      expect(UpdateService.openUrlCommand(UpdatePlatform.macos, 'https://x'), [
        'open',
        'https://x',
      ]);
      expect(UpdateService.openUrlCommand(UpdatePlatform.linux, 'https://x'), [
        'xdg-open',
        'https://x',
      ]);
      expect(
        UpdateService.openUrlCommand(UpdatePlatform.windows, 'https://x'),
        ['cmd.exe', '/c', 'start', '', 'https://x'],
      );
    });
  });
}
