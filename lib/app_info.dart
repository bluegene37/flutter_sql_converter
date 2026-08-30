/// Central app identity used by the About dialog and the update checker.
class AppInfo {
  AppInfo._();

  static const String appName = 'MagicSoftSQL';

  /// Must mirror pubspec.yaml's `version:` (without the `+build` suffix).
  /// The update checker compares this against GitHub release tags, so bump
  /// it in lockstep with pubspec.yaml on every release.
  static const String appVersion = '1.0.1';
}
