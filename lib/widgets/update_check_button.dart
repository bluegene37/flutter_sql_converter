import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/update/update_controller.dart';
import '../services/update/update_service.dart';
import '../theme/app_theme.dart';

/// Header icon that runs a user-triggered update check, styled like the
/// other header buttons. When an update is found the [UpdateGate] listener
/// opens the dialog; this button only gives feedback for the quiet outcomes
/// (up to date, offline).
class UpdateCheckButton extends StatelessWidget {
  const UpdateCheckButton({super.key, required this.controller});

  final UpdateController controller;

  Future<void> _check(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await controller.checkManually();

    final status = controller.lastResult?.status;
    if (status == UpdateStatus.upToDate) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${AppInfo.appName} ${controller.currentVersion} is up to date.',
          ),
        ),
      );
    } else if (status == UpdateStatus.failed) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not check for updates. Are you online?'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final isChecking = controller.isChecking;
        return Tooltip(
          message: 'Check for updates',
          child: InkWell(
            onTap: isChecking ? null : () => _check(context),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: colors.cardBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: isChecking
                  ? SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.accent,
                      ),
                    )
                  : Icon(
                      Icons.system_update_alt_rounded,
                      size: 15,
                      color: colors.textSecondary,
                    ),
            ),
          ),
        );
      },
    );
  }
}
