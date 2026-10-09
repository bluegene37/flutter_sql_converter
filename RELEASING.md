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

- `AppInfo.appVersion` in [lib/app_info.dart](lib/app_info.dart) — must equal
  the pubspec version **without** the `+build` suffix (a test enforces this).
  This is what the in-app update checker compares against release tags: if it
  lags, the app re-offers the version it already runs.
- `msix_config: msix_version:` in pubspec.yaml — four segments, e.g. `1.0.1.0`
- The version badge at the top of README.md

## In-app update checker contract

The app checks `https://api.github.com/repos/bluegene37/flutter_sql_converter/releases/latest`
(drafts and prereleases are excluded by that endpoint) at most once per 24h,
and offers the release when its tag outranks `AppInfo.appVersion`. For it to
work, every release must keep to:

1. **Tags are semver**: `vX.Y.Z`. A non-semver tag (e.g. `nightly`) is
   ignored by the app but hides newer real releases behind it — don't publish
   one as the latest release.
2. **Asset names keep their platform suffixes** (matched case-insensitively):
   - Windows: `*-Installer.exe` (inno_bundle's default naming) — used for
     silent in-place upgrade (`/SILENT /CLOSEAPPLICATIONS /NORESTART`).
   - macOS: `*.dmg` — the app opens the release page for a manual download.
3. **`AppInfo.appVersion` bumped in lockstep with pubspec.yaml** (see above).
4. The updater ships **with the next release users install** — installs made
   before it existed obviously never self-update.
5. The repo is public, so the GitHub API needs no auth. If it ever goes
   private, the updater breaks — do not embed a token in the app; rethink the
   feed instead (e.g. a public releases-only mirror).

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

## Code signing

### Windows

The CI release workflow automatically signs the Windows application executable and Inno Setup installer if code-signing secrets are configured in GitHub.

#### 1. Configuring CI signing (GitHub Actions)

Add two repository secrets in **GitHub repo → Settings → Secrets and variables → Actions**:

1. `WINDOWS_CERT_BASE64`: The base64-encoded string of your `.pfx` certificate file.
   - On Windows PowerShell, encode your PFX file:
     ```powershell
     [Convert]::ToBase64String([IO.File]::ReadAllBytes('path\to\cert.pfx')) | Set-Clipboard
     ```
   - On macOS/Linux:
     ```bash
     base64 -i path/to/cert.pfx | tr -d '\n' | pbcopy
     ```
2. `WINDOWS_CERT_PASSWORD`: The password protecting your `.pfx` certificate.

If these secrets are not configured, the CI workflow will cleanly skip the signing steps and produce unsigned releases.

#### 2. Signing locally (PowerShell)

Use `scripts/sign_windows.ps1` to sign release binaries with `signtool.exe`:

```powershell
# Build the application and installer
flutter build windows --release
dart run inno_bundle:build --release --no-app

# Sign with your certificate
.\scripts\sign_windows.ps1 -CertPath "C:\certs\my_cert.pfx" -CertPassword "<your-cert-password>"
```

For local testing without a commercial certificate, create and sign with a self-signed certificate:
```powershell
.\scripts\sign_windows.ps1 -CreateSelfSigned -CertPassword "<choose-a-password>"
```

#### 3. MSIX signing (Store & Enterprise)

- **Microsoft Store**: Submit the unsigned `.msix` created with `dart run msix:create`. Microsoft signs it automatically during certification.
- **Direct / Sideloading**: Set `certificate_path`, `certificate_password`, and `publisher` (matching the certificate Subject) in `pubspec.yaml` under `msix_config`.

<!-- Previous text:
### macOS

Unsigned apps trigger Gatekeeper. Users must right-click → Open the first time (or `xattr -d com.apple.quarantine`). To fix properly you need an Apple Developer ID certificate ($99/yr) and notarization (`codesign` + `notarytool`); add it to `scripts/build_macos_dmg.sh` once you have the certificate.

For internal/team distribution, unsigned builds are fine.
-->

<!-- Gene - Oct 7, 2026: Documented Apple Developer ID code signing, hardened runtime, and notarytool notarization flow -->
### macOS

macOS releases are distributed outside the App Store as a drag-to-install `.dmg` signed with an Apple **Developer ID Application** certificate and notarized by Apple so Gatekeeper opens the app seamlessly without security warnings.

#### 1. Signing & Notarization requirements

- **Developer ID Application Certificate**: Installed in macOS Keychain (Identity: `Developer ID Application: Gene Ray Medel (T7LB768N2Z)`).
- **Apple Development Team ID**: `T7LB768N2Z` (configured in `macos/Runner/Configs/AppInfo.xcconfig`).
- **Hardened Runtime & Entitlements**: Frameworks and app bundle are signed with `--options runtime` and `macos/Runner/Release.entitlements`.
- **Notarization**: Apple `notarytool` submits the DMG to Apple and staples the ticket with `stapler`.

<!-- Previous text:
#### 2. One-time Setup for Notarization (Apple ID App-Specific Password)

Generate an App-Specific Password at [appleid.apple.com](https://appleid.apple.com) under **Sign-In and Security → App-Specific Passwords**.

Store the credentials in your macOS Keychain:

```bash
xcrun notarytool store-credentials "notarytool-profile" \
  --apple-id "bluegene37@outlook.com" \
  --team-id "T7LB768N2Z"
```
*(Enter your generated app-specific password when prompted).*

#### 3. Building, Signing, and Notarizing Locally

Run the DMG build script with the notary profile:

```bash
NOTARY_PROFILE="notarytool-profile" bash scripts/build_macos_dmg.sh
```
-->

<!-- Gene - Oct 09, 2026: Updated instructions to document auto-detection of existing 'batterie-notary' profile -->
#### 2. Notarization Credentials (`batterie-notary`)

`scripts/build_macos_dmg.sh` automatically detects your existing stored Keychain profile `batterie-notary` (shared with the `batterie` and `snipsnap` projects).

If setting up on a new Mac or creating a fresh profile, generate an App-Specific Password at [appleid.apple.com](https://appleid.apple.com) and store it:

```bash
xcrun notarytool store-credentials "batterie-notary" \
  --apple-id "bluegene37@outlook.com" \
  --team-id "T7LB768N2Z"
```

#### 3. Building, Signing, and Notarizing Locally

Run the DMG build script (it will automatically sign, submit to Apple, staple, and verify):

```bash
bash scripts/build_macos_dmg.sh
```

This single command will:
1. Build `flutter build macos --release`.
2. Run `scripts/sign_macos_app.sh` to sign embedded frameworks (`objective_c.framework`, `FlutterMacOS.framework`, `App.framework`, and plugins) and `MagicSoftSQL.app` with hardened runtime, secure timestamps, and entitlements.
3. Create `build/MagicSoftSQL-<version>.dmg`.
4. Sign the DMG container with `Developer ID Application`.
5. Submit the DMG to Apple's Notary Service and wait for approval.
6. Staple the notarization ticket to the DMG (`xcrun stapler staple`).
7. Verify with Gatekeeper (`spctl --assess`).

<!-- Gene - Oct 7, 2026: Documented standalone sign_macos_app.sh and Gatekeeper "Move to Trash" notarization cause -->
#### Standalone App Signing (`scripts/sign_macos_app.sh`)

To sign an already-built `.app` bundle separately without rebuilding or packaging a DMG:

```bash
bash scripts/sign_macos_app.sh build/macos/Build/Products/Release/MagicSoftSQL.app
```

#### Why Gatekeeper Says "Will Damage Your Computer / Move to Trash"

When an app is downloaded from the internet, macOS applies the `com.apple.quarantine` attribute.
- If an app is **signed with Developer ID but NOT NOTARIZED by Apple**, macOS Gatekeeper rejects it with:
  *"MagicSoftSQL will damage your computer. You should move it to the Trash"* or *"Apple cannot check it for malicious software"*.
- **The fix is Apple Notarization**: Submitting the DMG to Apple (`xcrun notarytool submit`) and stapling the ticket (`xcrun stapler staple`). Once stapled, macOS validates the Apple ticket and allows users to open the app with a normal confirmation prompt.
- For local testing before notarization, you can strip quarantine with:
  ```bash
  xattr -d com.apple.quarantine /path/to/downloaded/MagicSoftSQL.dmg
  ```


#### 4. Configuring GitHub Actions CI (Optional)

To enable automated macOS signing and notarization on CI runners (`macos-latest`), add the following secrets in **GitHub repo → Settings → Secrets and variables → Actions**:

- `MACOS_CERTIFICATE_BASE64`: Base64-encoded `.p12` export of your Developer ID Application certificate and private key.
- `MACOS_CERTIFICATE_PASSWORD`: Password protecting the `.p12` file.
- `MACOS_APPLE_ID`: Your Apple ID email (`bluegene37@outlook.com`).
- `MACOS_APP_SPECIFIC_PASSWORD`: Your Apple app-specific password.
- `MACOS_TEAM_ID`: Your Apple Team ID (`T7LB768N2Z`).

If secrets are not configured, CI produces clean unsigned builds while local builds use your Keychain certificate.


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
