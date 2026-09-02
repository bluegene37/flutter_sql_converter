// QA entrypoint: the real app with the Flutter Driver extension enabled so
// /qa sessions can drive it engine-level (no OS input injection).
// Run: flutter run -d macos -t tool/qa_driver_main.dart
import 'package:flutter_driver/driver_extension.dart';

import 'package:flutter_sql_converter/main.dart' as app;

void main() {
  enableFlutterDriverExtension();
  app.main();
}
