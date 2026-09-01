import 'package:flutter/material.dart';
import '../../models/manual_topic.dart';

/// Centralized repository containing the offline documentation, knowledge base,
/// and contextual help guides for MagicSoftSQL.
class UserManualData {
  const UserManualData._();

  static const List<ManualTopic> topics = [
    ManualTopic(
      id: 'getting_started',
      title: 'Getting Started & Overview',
      subtitle: 'Core workflow, architecture, and workspace navigation',
      icon: Icons.rocket_launch_outlined,
      badge: 'Start Here',
      keywords: [
        'overview',
        'intro',
        'workflow',
        'navigation',
        'unipaas',
        'magic',
        'xpa',
        'modes',
        'setup',
        'tsql',
      ],
      sections: [
        ManualSection(
          title: 'System Architecture & Purpose',
          description:
              'MagicSoftSQL is a high-performance desktop workbench designed to analyze, parse, and convert legacy Magic UniPaaS and Magic XPA XML program repositories into clean, readable, and optimized Microsoft SQL Server (T-SQL) queries. It reconstructs complex database operations, subtasks, join conditions, and expressions without requiring access to a live UniPaaS runtime.',
          tags: ['Architecture', 'UniPaaS', 'T-SQL'],
        ),
        ManualSection(
          title: 'End-to-End Workflow',
          description:
              'The standard conversion workflow involves selecting an XML source folder, inspecting programs and task hierarchies, configuring parameter values, and generating T-SQL output.',
          steps: [
            'Click the folder path or Browse icon in the header bar to select your UniPaaS XML source directory.',
            'The app automatically indexes all Prg_*.xml files, mapping table identifiers with DataSources.xml.',
            'Search or filter the programs list in the left sidebar and select a program to inspect.',
            'Review the hierarchical task tree and active variables in the Parameters Inspector.',
            'Click "Generate SQL" (or press Cmd/Ctrl + G) to synthesize the T-SQL query.',
            'Copy the generated query to your clipboard or export it directly as a .sql file.',
          ],
          tip:
              'Ensure your source folder also contains DataSources.xml and Comps.xml so table and column names resolve to friendly database identifiers rather than internal numeric IDs.',
          shortcuts: ['Cmd + G', 'Ctrl + G', 'Cmd + S', 'Ctrl + S'],
          tags: ['Workflow', 'Getting Started', 'Export'],
        ),
        ManualSection(
          title: 'Navigating Application Modes',
          description:
              'The application features two primary operational modes accessible via the top-level segmented toggle in the header:',
          steps: [
            'SQL Generator Mode: Focuses on individual programs, hierarchical subtask breakdown, parameter configuration, and instant T-SQL query generation.',
            'Schema Browser Mode: Sweeps across the entire XML repository to construct a relational dependency graph, mapping foreign keys, table usages, and cross-program data flows.',
          ],
          tip:
              'Switching between modes preserves your active program selection, query output, and search filters.',
          shortcuts: ['F1'],
          tags: ['Modes', 'Navigation', 'Header'],
        ),
      ],
    ),

    ManualTopic(
      id: 'sql_generator',
      title: 'SQL Query Generator',
      subtitle: 'Syntax highlighting, parameter modes, and query export',
      icon: Icons.terminal_outlined,
      badge: 'Core Tool',
      keywords: [
        'sql',
        'generator',
        'query',
        'syntax',
        'declare',
        'inject',
        'export',
        'clipboard',
        'copy',
        'formatting',
      ],
      sections: [
        ManualSection(
          title: 'Interactive Query Workbench',
          description:
              'The central query output workbench renders synthesized T-SQL queries with full syntax highlighting, line numbers, and clean indentation. Body text, keywords, strings, parameters, comments, and numeric literals are styled with semantic palette colors tuned for readability in both light and dark modes.',
          tags: ['Editor', 'Syntax Highlighting', 'T-SQL'],
        ),
        ManualSection(
          title: 'Parameter Generation Modes',
          description:
              'You can control how parameters are represented in the generated SQL using the "Inject Values" toggle in the editor toolbar:',
          steps: [
            'Parameterized (Default / Inactive): Generates standard T-SQL DECLARE statements at the top of the query with inferred SQL types (e.g., DECLARE @CustID INT = ...), preserving clean parameterization suitable for stored procedures.',
            'Injected Values (Active): Inlines the current parameter values directly into WHERE clauses and JOIN conditions, ideal for immediate ad-hoc execution in SQL Server Management Studio (SSMS) or Azure Data Studio.',
          ],
          tip:
              'When Inject Values is disabled, any modified parameter values in the right sidebar are automatically reflected in the default DECLARE assignments.',
          tags: ['Parameters', 'DECLARE', 'Injection'],
        ),
        ManualSection(
          title: 'Copying & Exporting Queries',
          description:
              'Seamlessly transition generated queries into external database tools, scripts, or version control repositories.',
          steps: [
            'Click the "Copy SQL" button (or press Cmd/Ctrl + C with text selected) to copy the full query buffer.',
            'Click "Export .sql" (or press Cmd/Ctrl + S) to open the native save dialog and write the query to a standalone .sql script file on disk.',
          ],
          shortcuts: ['Cmd + S', 'Ctrl + S', 'Cmd + G', 'Ctrl + G'],
          tags: ['Export', 'Clipboard', 'Files'],
        ),
      ],
    ),

    ManualTopic(
      id: 'parameters',
      title: 'Parameters & Variables Inspector',
      subtitle: 'Virtuals, arguments, typing, and mock data injection',
      icon: Icons.tune_outlined,
      badge: 'Inspector',
      keywords: [
        'parameters',
        'variables',
        'virtuals',
        'arguments',
        'types',
        'values',
        'fields',
        'mock',
        'inputs',
      ],
      sections: [
        ManualSection(
          title: 'Live Parameter Detection',
          description:
              'The Parameters Inspector in the right sidebar scans selected XML programs to discover all input arguments, virtual variables, and field definitions. It automatically deduplicates variables and resolves their corresponding SQL data types (e.g., VARCHAR, INT, DATETIME, NUMERIC).',
          tags: ['Detection', 'Virtuals', 'Typing'],
        ),
        ManualSection(
          title: 'Smart Variable Filtering',
          description:
              'UniPaaS programs often define dozens of internal screen virtuals or loop counters. MagicSoftSQL automatically filters out unused variables, displaying only the parameters that actively participate in WHERE conditions, JOIN ON clauses, or SQL expressions for the selected program or task.',
          tip:
              'If a program has no active database parameters or no tables, the parameter panel automatically collapses to give full screen width to the query workbench.',
          tags: ['Smart Filter', 'Optimization'],
        ),
        ManualSection(
          title: 'Editing Values & Re-generating',
          description:
              'You can enter test values into any parameter input field. Press Enter or click Generate SQL to immediately refresh the query with the updated values.',
          steps: [
            'Click on any parameter text input field in the right panel.',
            'Type a new test value (e.g. numeric ID, date string YYYYMMDD, or text).',
            'Press Cmd/Ctrl + G or Enter to re-synthesize the SQL query.',
          ],
          shortcuts: ['Cmd + G', 'Ctrl + G', 'Enter'],
          tags: ['Input', 'Testing', 'Values'],
        ),
      ],
    ),

    ManualTopic(
      id: 'program_tree',
      title: 'XML Program Tree & Tasks',
      subtitle: 'Task hierarchy, subtask scoping, and link operations',
      icon: Icons.account_tree_outlined,
      badge: 'Structure',
      keywords: [
        'tasks',
        'subtasks',
        'tree',
        'hierarchy',
        'programs',
        'isolation',
        'links',
        'joins',
        'root',
      ],
      sections: [
        ManualSection(
          title: 'Hierarchical Task Exploration',
          description:
              'UniPaaS programs are structured as recursive trees of tasks (Root Task, Task 1.1, Task 1.2, etc.). When a program is selected, the left panel expands to reveal the full task tree with badges indicating the number of database tables and joins in each task level.',
          tags: ['Hierarchy', 'Subtasks', 'Tree'],
        ),
        ManualSection(
          title: 'Task-Level SQL Scoping',
          description:
              'By default, selecting a program generates a comprehensive script covering all tasks and subtasks. You can also isolate a specific subtask by clicking directly on that task node in the tree.',
          steps: [
            'Click on the parent program in the programs list.',
            'Click on any child task in the tree (e.g., Task 1.2 "Update Order Lines").',
            'The workbench immediately focuses on that specific task, synthesizing an isolated SELECT or UPDATE query and showing only the parameters relevant to that task.',
            'Click the program header or "All Tasks" to return to the full-program view.',
          ],
          tip:
              'Collapsing a task branch in the tree hides child tasks without altering the generated SQL for the overall program.',
          tags: ['Scoping', 'Subqueries', 'Isolation'],
        ),
        ManualSection(
          title: 'Database Links & Join Operations',
          description:
              'Each task node inspects its underlying DB and LNK elements. MagicSoftSQL identifies the primary transaction table and resolves all joined tables, link conditions, and expressions.',
          tags: ['LNK', 'Joins', 'Transactions'],
        ),
      ],
    ),

    ManualTopic(
      id: 'schema_browser',
      title: 'Schema Relationship Browser',
      subtitle: 'Multi-file sweeping, graph caching, and table inspector',
      icon: Icons.hub_outlined,
      badge: 'Schema',
      keywords: [
        'schema',
        'relationships',
        'graph',
        'tables',
        'foreign keys',
        'scanner',
        'cache',
        'inspector',
        'columns',
        'dependencies',
      ],
      sections: [
        ManualSection(
          title: 'On-Demand Relationship Discovery',
          description:
              'Opening the Schema tab never starts a sweep on its own. It reuses the cached relationship graph when the source folder still matches it, and otherwise shows a banner offering to scan. The scanner analyzes Link conditions (<LNK>) to deduce foreign key relationships and table dependencies across your entire UniPaaS application.',
          tags: ['Scanner', 'Dependencies', 'Foreign Keys'],
        ),
        ManualSection(
          title: 'High-Performance Graph Caching',
          description:
              'Scanning thousands of XML files can be IO-intensive. MagicSoftSQL hashes directory metadata to build a persistent cache on disk. Subsequent launches load the complete relationship graph instantaneously in milliseconds.',
          tip:
              'If you modify XML files externally, click "Rescan" in the header bar (or press Cmd/Ctrl + R). One rescan refreshes the program list and the relationship graph together, so both tabs come back up to date in a single pass.',
          shortcuts: ['Cmd + R', 'Ctrl + R'],
          tags: ['Performance', 'Cache', 'Hashing'],
        ),
        ManualSection(
          title: 'Interactive Table Inspector & Deep Linking',
          description:
              'Clicking any table card in the Schema Browser opens the Table Inspector dialog:',
          steps: [
            'View the full list of database columns, data types, and primary keys.',
            'Inspect Outgoing Links (tables this table queries or points to).',
            'Inspect Incoming Links (other tables and programs that reference this table).',
            'Click on any referenced program name in the list to jump directly to that program in SQL Generator Mode.',
          ],
          tags: ['Inspector', 'Columns', 'Deep Linking'],
        ),
      ],
    ),

    ManualTopic(
      id: 'expressions',
      title: 'Expressions & Magic Translation',
      subtitle: 'Magic function translation, globals, and join synthesis',
      icon: Icons.transform_outlined,
      badge: 'Engine',
      keywords: [
        'expressions',
        'functions',
        'magic',
        'translation',
        'trim',
        'if',
        'dstr',
        'flip',
        'globals',
        'mainprogram',
        'joins',
        'synthesizer',
      ],
      sections: [
        ManualSection(
          title: 'UniPaaS Expression Transpilation',
          description:
              'Magic UniPaaS utilizes a proprietary expression grammar with 1-based indexing and unique built-in functions. The parser transpiles these expressions into idiomatic T-SQL:',
          steps: [
            'TRIM(x) -> LTRIM(RTRIM(x))',
            'IF(cond, val1, val2) -> CASE WHEN cond THEN val1 ELSE val2 END',
            'DSTR(date, format) -> CONVERT / FORMAT string representations',
            'FLIP(x) -> REVERSE(x)',
            'MID(str, start, len) -> SUBSTRING(str, start, len)',
            'STR(num, len, dec) -> STR(num, len, dec)',
            'Date & Time arithmetic -> DATEADD / DATEDIFF equivalents',
          ],
          tags: ['Functions', 'Transpiler', 'T-SQL Grammar'],
        ),
        ManualSection(
          title: 'Global Variable & Component Resolution',
          description:
              'Magic programs frequently reference global system variables and user session IDs using the special syntax {32768, x}. The parser resolves {32768, x} tokens against MainProgram headers and Comps.xml definitions, converting them into meaningful variable identifiers (such as @g_UserID or @g_CompanyCode).',
          tip:
              'Ensure ProgramHeaders.xml and Comps.xml are present in the folder for optimal global variable naming.',
          tags: ['MainProgram', 'Globals', 'Comps'],
        ),
        ManualSection(
          title: 'Join Synthesizer Modes',
          description:
              'UniPaaS <LNK> elements specify operational modes such as Link Read (R), Link Write (W), and Link Create (C). The generator maps Link Read to LEFT OUTER JOIN (or INNER JOIN when accompanied by positive validation conditions) and maps Link Write/Create to target UPDATE or INSERT structures.',
          tags: ['Joins', 'LNK', 'Outer Join'],
        ),
      ],
    ),

    ManualTopic(
      id: 'shortcuts',
      title: 'Keyboard Shortcuts Cheat Sheet',
      subtitle: 'Master key combinations for rapid workbench navigation',
      icon: Icons.keyboard_outlined,
      badge: 'Hotkeys',
      keywords: [
        'shortcuts',
        'hotkeys',
        'keyboard',
        'cheatsheet',
        'f1',
        'cmd',
        'ctrl',
        'enter',
        'search',
      ],
      sections: [
        ManualSection(
          title: 'Global Application Hotkeys',
          description:
              'These shortcuts are active throughout the entire application window at all times:',
          steps: [
            'F1 or Cmd/Ctrl + ? : Open In-App User Manual & Help Center',
            'Cmd/Ctrl + G or Cmd/Ctrl + Enter : Synthesize / Re-generate SQL Query',
            'Cmd/Ctrl + F : Focus Search Field (Programs search or Schema search)',
            'Cmd/Ctrl + S : Export SQL Query to .sql file on disk',
            'Cmd/Ctrl + R : Rescan XML Source Folder & Reload Metadata',
          ],
          shortcuts: [
            'F1',
            'Cmd + ?',
            'Ctrl + ?',
            'Cmd + G',
            'Ctrl + G',
            'Cmd + Enter',
            'Ctrl + Enter',
            'Cmd + F',
            'Ctrl + F',
            'Cmd + S',
            'Ctrl + S',
            'Cmd + R',
            'Ctrl + R',
          ],
          tags: ['Global', 'Hotkeys'],
        ),
        ManualSection(
          title: 'Editor & Dialog Navigation',
          description:
              'Standard key combinations for managing text selection, code copy, and dialog states:',
          steps: [
            'Cmd/Ctrl + C : Copy selected SQL text or query buffer',
            'Cmd/Ctrl + A : Select entire generated SQL query',
            'Escape : Dismiss open dialogs (User Manual, Table Details, About App)',
            'Tab / Shift + Tab : Move focus between parameter input fields',
          ],
          shortcuts: ['Cmd + C', 'Ctrl + C', 'Cmd + A', 'Ctrl + A', 'Esc', 'Tab'],
          tags: ['Editor', 'Navigation'],
        ),
      ],
    ),

    ManualTopic(
      id: 'troubleshooting',
      title: 'Settings, Permissions & Troubleshooting',
      subtitle: 'Folder configuration, metadata resolution, and offline updates',
      icon: Icons.build_circle_outlined,
      badge: 'Support',
      keywords: [
        'troubleshooting',
        'settings',
        'permissions',
        'errors',
        'datasources',
        'folder',
        'updates',
        'offline',
        'storage',
      ],
      sections: [
        ManualSection(
          title: 'XML Folder Structure & Missing Files',
          description:
              'MagicSoftSQL requires a folder containing exported XML programs. For full schema resolution, the folder or its parent should ideally contain the following standard files:',
          steps: [
            'Prg_*.xml : Individual program definitions (required).',
            'DataSources.xml : Maps data source numeric IDs to real table and column names (highly recommended).',
            'ProgramHeaders.xml : Defines program titles, execution order, and entry points.',
            'Comps.xml : Defines external component definitions and shared schemas.',
          ],
          tip:
              'If DataSources.xml is missing, the app will still generate valid T-SQL queries using fallback table identifiers (e.g. Table_10, Column_5).',
          tags: ['Folder', 'XML', 'Prg'],
        ),
        ManualSection(
          title: 'Local Storage & Preferences',
          description:
              'Your last selected XML source folder path and preferences are automatically persisted to local storage using SharedPreferences. When launching the app, your previous session is restored seamlessly without requiring re-configuration.',
          tags: ['Storage', 'Preferences'],
        ),
        ManualSection(
          title: 'Software Updates & Air-Gapped Environments',
          description:
              'The app includes an integrated update checker that queries GitHub Releases for newer builds. In enterprise or air-gapped environments without external internet access, update checks will fail gracefully without interrupting any query generation or schema browsing features.',
          tags: ['Updates', 'Offline', 'Air-gapped'],
        ),
      ],
    ),
  ];

  /// Finds a topic by its unique identifier.
  static ManualTopic? getTopicById(String id) {
    for (final topic in topics) {
      if (topic.id == id) return topic;
    }
    return null;
  }
}
