import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Sickler's Warriors — shared form controls (FRONTEND-1).
///
/// Field styling lives in [AppTheme]; these thin helpers standardise the
/// handful of recurring custom controls (search, segmented primary forms).

/// Search field used across lists (doctors, education, community).
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.hintText,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  final String hintText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: IconButton(
          tooltip: tr('common.clearSearch'),
          icon: const Icon(Icons.close),
          onPressed: () {
            controller?.clear();
            onChanged?.call('');
          },
        ),
      ),
    );
  }
}

/// Label above an input, matching the field style.
class AppFieldLabel extends StatelessWidget {
  const AppFieldLabel({super.key, required this.text, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text.rich(
        TextSpan(
          text: text,
          children: [
            if (required)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: AppColors.emergency),
              ),
          ],
        ),
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

/// Emphasized helper text aligned with the design system.
class AppHelperText extends StatelessWidget {
  const AppHelperText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}