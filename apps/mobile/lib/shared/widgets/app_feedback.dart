import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Sickler's Warriors — shared feedback helpers (FRONTEND-1).
///
/// Consistent confirmation dialogs, snackbars and banners with calm, safe copy.

/// Shows a confirmation dialog and resolves `true` when confirmed.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: destructive ? AppColors.emergency : null,
            foregroundColor: destructive ? AppColors.textOnEmergency : null,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Shows a short confirmation toast.
void showSuccess(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                color: AppColors.success, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
        action: actionLabel == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                textColor: AppColors.textOnDark,
                onPressed: onAction ?? () {},
              ),
      ),
    );
}

/// Shows a neutral/error toast.
void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Presents a material banner (used by emergency/important notices).
void showBanner(
  ScaffoldMessengerState messenger,
  String message, {
  bool warning = false,
  VoidCallback? onAction,
}) {
  messenger
    ..hideCurrentMaterialBanner()
    ..showMaterialBanner(
      MaterialBanner(
        backgroundColor: warning ? AppColors.warning : AppColors.navy,
        leading: Icon(
          warning ? Icons.warning_amber_rounded : Icons.info_outline,
          color: AppColors.textOnDark,
        ),
        content: Text(
          message,
          style: const TextStyle(color: AppColors.textOnDark),
        ),
        actions: [
          TextButton(
            onPressed: onAction ??
                () {
                  messenger.hideCurrentMaterialBanner();
                },
            child: Text(
              onAction == null ? 'Dismiss' : 'View',
              style: const TextStyle(color: AppColors.textOnDark),
            ),
          ),
        ],
      ),
    );
}