# Releasing MagicSoftSQL

Desktop-only release guide: **Windows** (Inno Setup installer + optional MSIX)
and **macOS** (DMG).

App identity: `dev.genexis.magicsoftsql` · Display name: **MagicSoftSQL**

## Versioning

The single source of truth is `version:` in [pubspec.yaml](pubspec.yaml)
(`1.0.0+1` — semantic version `+` build number). It flows automatically into
the macOS bundle (`CFBundleShortVersionString`) and the Windows exe metadata
(`FileVersion`/`ProductVersion` via `Runner.rc`).

When bumping, also update:

- `msix_config: msix_version:` in pubspec.yaml — four segments, e.g. `1.0.1.0`
- The version badge at the top of README.md

## Release steps

1. Bump the version (see above).
2. Verify locally:
   ```bash
   flutter analyze && flutter test
   ```
3. Commit, tag, and push:
   ```bash
   git tag v1.0.0 && git push origin main --tags
   ```
4. The [Release workflow](.github/workflows/release.yml) builds the Windows
   installer and macOS DMG and attaches both to a GitHub release.

## Building locally instead

### macOS DMG (on a Mac)

```bash
bash scripts/build_macos_dmg.sh
# → build/MagicSoftSQL-<version>.dmg
```

### Windows installer (on Windows)

Requires Inno Setup 6 (`winget install JRSoftware.InnoSetup`; CI runners have it preinstalled):

```bash
flutter build windows --release
dart run inno_bundle:build --release --no-app
# → build/windows/x64/installer/*.exe
```

### MSIX (optional, for Microsoft Store / enterprise deployment)

```bash
dart run msix:create
```

## Code signing status

Neither platform is signed yet. Consequences and fixes:

- **macOS**: unsigned apps trigger Gatekeeper. Users must right-click → Open
  the first time (or `xattr -d com.apple.quarantine`). To fix properly you
  need an Apple Developer ID certificate ($99/yr) and notarization
  (`codesign` + `notarytool`); add it to `scripts/build_macos_dmg.sh` once
  you have the certificate.
- **Windows**: unsigned installers show a SmartScreen warning. Fix requires
  an Authenticode/EV certificate, or distributing via the Microsoft Store
  (MSIX), which signs through the Store.

For internal/team distribution the unsigned builds are fine.

## Icons

All platform icons are generated from `assets/icon/app_icon.png` (full-bleed
1024×1024, cropped from `assets/logo.png`):

```bash
dart run flutter_launcher_icons
```

## Invariants — do not change

- `inno_bundle: id:` in pubspec.yaml is the installer's upgrade identity
  (AppId). Changing it makes new installs stop upgrading old ones.
- `PRODUCT_BUNDLE_IDENTIFIER` (macOS) and `identity_name` (MSIX) are the
  app's identity: `dev.genexis.magicsoftsql`.

## Pre-release checklist

- [ ] `version:` bumped in pubspec.yaml (+ `msix_version`, README badge)
- [ ] `flutter analyze` clean, `flutter test` passing
- [ ] App runs from a **release** build (`flutter run -d macos --release`), not just debug
- [ ] Icons render correctly in the Dock / taskbar
- [ ] No developer-machine paths or debug output in the shipped build
- [ ] Tag pushed; CI release workflow green; installer + DMG attached to the GitHub release
