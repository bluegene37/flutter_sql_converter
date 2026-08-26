# UniPaaS SQL Generator

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Web-4E73DF)](#)
[![License](https://img.shields.io/badge/License-Proprietary-informational)](#)

A high-performance desktop and web application designed to analyze, parse, and convert **Magic / UniPaaS / XPA** XML program repositories into clean, optimized, production-grade **Microsoft SQL Server (T-SQL)** queries and scripts.

---

## 🚀 Key Features

- **Blazing-Fast XML Streaming Engine**: Uses an event-based XML parser (`XmlEvent`) to parse massive repositories (tested across 7,750+ XML programs, 30,000+ tasks, and 41,000+ joins) in seconds with minimal memory footprint.
- **Accurate UniPaaS Semantics**:
  - **DataViews & Schema Resolution**: Maps physical tables, column ISNs, types, and index definitions against `DataSources.xml` and multi-component `Comps.xml`.
  - **Intelligent Link Mapping**:
    - `Mode="R"` (Link Query): Distinguishes unique vs. non-unique index segments. Generates `LEFT OUTER JOIN` when guaranteed single-row, or correlated `OUTER APPLY (SELECT TOP 1 ... ORDER BY ...)` when ordering matters.
    - `Mode="J"`: Converted to `INNER JOIN ... ON ...`.
    - `Mode="O"`: Converted to `LEFT OUTER JOIN ... ON ...`.
    - `Mode="W"` (Link Write): Automatically generates faithful `UPDATE` statements with column assignments.
    - `Mode="A"` (Link Create): Automatically generates guarded `IF NOT EXISTS (...) BEGIN INSERT INTO ... END;` scripts.
  - **Locates & Ranges**: Accurately maps 1-based expression positions to `=`, `>=`, `<=`, and `BETWEEN` predicates.
  - **Main Program Globals (`{32768, N}`)**: Resolves root program variables into correctly typed T-SQL parameters (`@g_...`).
  - **Hierarchical Ancestor Propagation (`{1, N}`, `{2, N}`)**: Resolves ancestor task columns as scoped `@parent_...` parameters with provenance notes.
- **Interactive Developer UI**:
  - **Dual Mode Generation**: Toggle between parameterized T-SQL (`@variables` with `DECLARE` blocks) and executable literal values (`"values"`).
  - **Dynamic Parameters Inspector**: Edit variable values in real-time to generate instant executable queries.
  - **T-SQL Syntax Highlighting**: Custom, high-contrast semantic syntax highlighter with line-number gutters.
  - **Export & Clipboard**: 1-click **Copy to Clipboard** and **Export to File (`.sql`)**.
  - **Desktop Keyboard Shortcuts**: Full hotkey support for power users.
  - **Adaptive Themes**: Refined Light and Dark themes designed for prolonged developer workflows.

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| <kbd>Cmd</kbd> / <kbd>Ctrl</kbd> + <kbd>G</kbd> or <kbd>Enter</kbd> | **Generate SQL** query |
| <kbd>Cmd</kbd> / <kbd>Ctrl</kbd> + <kbd>F</kbd> | Focus **Search Programs** filter |
| <kbd>Cmd</kbd> / <kbd>Ctrl</kbd> + <kbd>S</kbd> | **Export SQL** to file (`.sql`) |
| <kbd>Cmd</kbd> / <kbd>Ctrl</kbd> + <kbd>R</kbd> | **Rescan** XML source directory |

---

## 🏗️ Architecture & Project Structure

```
lib/
├── main.dart                      # Application entry point & theme configuration
├── models/
│   └── unipaas_models.dart        # Data models (Tasks, Joins, Columns, Conditions, Tables)
├── services/
│   ├── schema_service.dart        # DataSources.xml & Comps.xml streaming schema loader
│   ├── xml_parser_service.dart    # UniPaaS AST parser, expression evaluator & task resolver
│   ├── sql_generator_service.dart # T-SQL generator (SELECT, INSERT, UPDATE, APPLY)
│   └── settings_service.dart      # Persistent directory & workspace settings
├── theme/
│   └── app_theme.dart             # Semantic design tokens for Light and Dark modes
├── views/
│   └── main_view.dart             # Main 3-pane workbench UI with drag handles
└── widgets/
    ├── drag_handle.dart           # Smooth horizontal split-pane resize handles
    └── sql_view.dart              # Syntax highlighter & line gutter canvas
```

---

## 🛠️ Getting Started

### Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) `^3.12.2` or later.
- Desktop development dependencies for your OS (Xcode for macOS, Visual Studio C++ for Windows, or Clang/CMake for Linux).

### Running the Application

1. **Clone the repository**:
   ```bash
   git clone https://github.com/your-org/flutter_sql_converter.git
   cd flutter_sql_converter
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run on macOS / Desktop**:
   ```bash
   flutter run -d macos
   # or for Windows:
   # flutter run -d windows
   ```

4. **Select XML Source Directory**:
   - On first launch, the app defaults to the local `source/` directory if present.
   - Click the folder picker icon in the header to point to your UniPaaS exported XML folder.

---

## 🧪 Testing & Verification

Run the comprehensive unit, widget, and corpus verification suites:

```bash
# Run unit & widget tests
flutter test test/widget_test.dart test/parser_semantics_test.dart

# Run golden rendering tests
flutter test test/sql_view_golden_test.dart

# Run static code analysis
flutter analyze
```

---

## 📄 License

This software is proprietary and confidential. All rights reserved.
