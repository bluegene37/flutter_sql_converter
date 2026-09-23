import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/unipaas_models.dart';
import '../theme/app_theme.dart';
import 'sql_view.dart';

/// Opens the uniPaaS-style "SQL Command" inspector dialog.
Future<void> showDirectSqlCommandDialog(
  BuildContext context, {
  required ParsedTask task,
  required String programName,
  required String programNumber,
}) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => DirectSqlCommandDialog(
      task: task,
      programName: programName,
      programNumber: programNumber,
    ),
  );
}

class DirectSqlCommandDialog extends StatefulWidget {
  final ParsedTask task;
  final String programName;
  final String programNumber;

  const DirectSqlCommandDialog({
    super.key,
    required this.task,
    required this.programName,
    required this.programNumber,
  });

  @override
  State<DirectSqlCommandDialog> createState() => _DirectSqlCommandDialogState();
}

class _DirectSqlCommandDialogState extends State<DirectSqlCommandDialog> {
  int _activeParamTab = 0; // 0: Input Arguments, 1: Output Arguments

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final direct = widget.task.directSql;
    final size = MediaQuery.of(context).size;
    final availableWidth = math.max(320.0, size.width - 48.0);
    final availableHeight = math.max(300.0, size.height - 48.0);
    final dialogWidth = (size.width * 0.85).clamp(360.0, 960.0).clamp(0.0, availableWidth);
    final dialogHeight = (size.height * 0.88).clamp(400.0, 780.0).clamp(0.0, availableHeight);

    final titlePath = widget.task.numberWithin(widget.programNumber);
    final titleText = 'SQL Command: $titlePath - ${widget.programName} · ${widget.task.description}';

    return Dialog(
      backgroundColor: colors.panelBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
              decoration: BoxDecoration(
                color: colors.headerBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colors.accentSecondary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.terminal,
                      size: 16,
                      color: colors.accentSecondary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      titleText,
                      style: GoogleFonts.outfit(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: colors.textMuted),
                    splashRadius: 18,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: direct == null
                  ? Center(
                      child: Text(
                        'No Direct SQL found for this task.',
                        style: GoogleFonts.inter(color: colors.textMuted),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Database Selection Group
                          _buildDatabaseSelectionCard(colors, direct),
                          const SizedBox(height: 12),

                          // SQL Command Section
                          Expanded(
                            flex: 3,
                            child: _buildSqlCommandCard(colors, direct),
                          ),
                          const SizedBox(height: 12),

                          // SQL Parameters Section
                          Expanded(
                            flex: 2,
                            child: _buildParametersCard(colors, direct),
                          ),
                        ],
                      ),
                    ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: colors.headerBg,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  if (direct != null) ...[
                    Expanded(
                      child: Text(
                        '${direct.inputArguments.length} input params · ${direct.outputArguments.length} output columns',
                        style: GoogleFonts.inter(
                          color: colors.textMuted,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else ...[
                    const Spacer(),
                  ],
                  if (direct != null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 14),
                      label: const Text('Copy SQL'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.textPrimary,
                        side: BorderSide(color: colors.border),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: direct.sqlStatement));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Direct SQL query copied to clipboard!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: colors.textOnAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatabaseSelectionCard(AppColors colors, DirectSqlInfo direct) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DATABASE SELECTION',
            style: GoogleFonts.inter(
              color: colors.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildDbField(colors, 'Database', direct.database.isEmpty ? '(Default)' : direct.database),
              _buildDbField(colors, 'Result Database', direct.resultDatabase.isEmpty ? '(Default)' : direct.resultDatabase),
              _buildDbField(colors, 'Task Type', 'Direct SQL'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDbField(AppColors colors, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: GoogleFonts.inter(
            color: colors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: colors.codeBg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: colors.border),
          ),
          child: Text(
            value,
            style: GoogleFonts.firaCode(
              color: colors.accent,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSqlCommandCard(AppColors colors, DirectSqlInfo direct) {
    return Container(
      decoration: BoxDecoration(
        color: colors.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.headerBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Text(
                  'SQL COMMAND',
                  style: GoogleFonts.inter(
                    color: colors.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: direct.sqlStatement));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('SQL query copied!'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy, size: 12, color: colors.accent),
                        const SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
              child: SqlView(sql: direct.sqlStatement),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParametersCard(AppColors colors, DirectSqlInfo direct) {
    return Container(
      decoration: BoxDecoration(
        color: colors.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: colors.headerBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                _buildParamTabButton(
                  colors: colors,
                  title: 'Input Arguments',
                  count: direct.inputArguments.length,
                  isSelected: _activeParamTab == 0,
                  onTap: () => setState(() => _activeParamTab = 0),
                ),
                const SizedBox(width: 8),
                _buildParamTabButton(
                  colors: colors,
                  title: 'Output Arguments',
                  count: direct.outputArguments.length,
                  isSelected: _activeParamTab == 1,
                  onTap: () => setState(() => _activeParamTab = 1),
                ),
              ],
            ),
          ),
          Expanded(
            child: _activeParamTab == 0
                ? _buildInputArgumentsList(colors, direct)
                : _buildOutputArgumentsList(colors, direct),
          ),
        ],
      ),
    );
  }

  Widget _buildParamTabButton({
    required AppColors colors,
    required String title,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colors.panelBg : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? colors.border : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                color: isSelected ? colors.textPrimary : colors.textMuted,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.accent.withValues(alpha: 0.15)
                    : colors.codeBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.firaCode(
                  color: isSelected ? colors.accent : colors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArgumentsList(AppColors colors, DirectSqlInfo direct) {
    if (direct.inputArguments.isEmpty) {
      return Center(
        child: Text(
          'No input arguments (:1, :2, etc.) for this Direct SQL query.',
          style: GoogleFonts.inter(color: colors.textMuted, fontSize: 12),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: direct.inputArguments.length,
      separatorBuilder: (_, _) => Divider(color: colors.border.withValues(alpha: 0.4), height: 1),
      itemBuilder: (context, index) {
        final arg = direct.inputArguments[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            children: [
              Container(
                width: 32,
                padding: const EdgeInsets.symmetric(vertical: 2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  ':${arg.index}',
                  style: GoogleFonts.firaCode(
                    color: colors.accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  arg.expressionSyntax.isNotEmpty ? arg.expressionSyntax : '(exp ${arg.expVal})',
                  style: GoogleFonts.firaCode(
                    color: colors.textPrimary,
                    fontSize: 11.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (arg.expVal.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  'Exp #${arg.expVal}',
                  style: GoogleFonts.firaCode(
                    color: colors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildOutputArgumentsList(AppColors colors, DirectSqlInfo direct) {
    if (direct.outputArguments.isEmpty) {
      return Center(
        child: Text(
          'No output arguments mapped for this Direct SQL query.',
          style: GoogleFonts.inter(color: colors.textMuted, fontSize: 12),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: direct.outputArguments.length,
      separatorBuilder: (_, _) => Divider(color: colors.border.withValues(alpha: 0.4), height: 1),
      itemBuilder: (context, index) {
        final arg = direct.outputArguments[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            children: [
              Container(
                width: 28,
                padding: const EdgeInsets.symmetric(vertical: 2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.accentSecondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${arg.index}',
                  style: GoogleFonts.firaCode(
                    color: colors.accentSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  arg.varName,
                  style: GoogleFonts.firaCode(
                    color: colors.textPrimary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (arg.sqlType.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.codeBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    arg.sqlType,
                    style: GoogleFonts.firaCode(
                      color: colors.textSecondary,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
