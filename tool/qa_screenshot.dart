// Saves an engine-level screenshot of the running QA app (only the Flutter
// surface, never the desktop) so /qa reports can keep evidence on disk.
// Run: dart run tool/qa_screenshot.dart <vm-service-ws-uri> <out.png>
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('usage: qa_screenshot.dart <ws://vm-service/ws> <out.png>');
    exit(64);
  }
  final driver = await FlutterDriver.connect(
    dartVmServiceUrl: args[0],
    printCommunication: false,
  );
  try {
    final bytes = await driver.screenshot();
    await File(args[1]).writeAsBytes(bytes);
    stdout.writeln('wrote ${args[1]} (${bytes.length} bytes)');
  } finally {
    await driver.close();
  }
}
