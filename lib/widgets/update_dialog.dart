import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_info.dart';
import '../services/update/update_controller.dart';
import '../services/update/update_info.dart';
import '../theme/app_theme.dart';

/// Modal shown when a newer release is available. Offers install/download,
/// a session-only "Later", and a persistent "Skip this version".
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key, required this.controller});

  final UpdateController controller;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final update = controller.availableUpdate;
        if (update == null) {
          // Update dismissed while the dialog was open (e.g. install handoff).
          return const SizedBox.shrink();
        }
        final silentInstall = controller.platform == UpdatePlatform.windows &&
            update.asset != null;

        return AlertDialog(
          backgroundColor: colors.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: colors.border),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          title: Row(
            children: [
              Icon(Icons.system_update_alt_rounded, color: colors.accent),
              const SizedBox(width: 12),
              Text(
                'Update Available',
                style: GoogleFonts.outfit(
                  color: colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${AppInfo.appName} ${update.version} is available. '
                  'You are on ${controller.currentVersion}.',
                  style: GoogleFonts.inter(
                    color: colors.textPrimary,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  silentInstall
                      ? 'The update installs in the background and the app '
                          'restarts automatically.'
                      : 'The download page opens in your browser.',
                  style: GoogleFonts.inter(
                    color: colors.textSecondary,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
                if (controller.isDownloading) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: controller.downloadProgress,
                      color: colors.accent,
                      backgroundColor: colors.panelBg,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Downloading… '
                    '${(controller.downloadProgress * 100).toStringAsFixed(0)}%',
                    style: GoogleFonts.inter(
                      color: colors.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
                if (controller.installError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Update failed: ${controller.installError}. '
                    'Use Download to get it manually.',
                    style: GoogleFonts.inter(
                      color: const Color(0xFFEF4444),
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: controller.isDownloading
                  ? null
                  : () async {
                      final navigator = Navigator.of(context);
                      await controller.skipAvailableVersion();
                      navigator.pop();
                    },
              child: Text(
                'Skip this version',
                style: GoogleFonts.inter(
                  color: colors.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: controller.isDownloading
                  ? null
                  : () {
                      controller.dismiss();
                      Navigator.of(context).pop();
                    },
              child: Text(
                'Later',
                style: GoogleFonts.inter(
                  color: colors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton(
              onPressed:
                  controller.isDownloading ? null : controller.applyUpdate,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.textOnAccent,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                silentInstall ? 'Install & Restart' : 'Download',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
