import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/l10n/app_localizations.dart' show AppLocalizations;
import '../../core/l10n/locale_controller.dart' show LocaleScope;
import '../../core/theme/theme_controller.dart' show ThemeScope;

/// Appearance & language sheet: real, device-persisted theme (System/Light/
/// Dark) and language (EN / Kiswahili / follow device) controls.
///
/// Opens from Profile and the app-bar "more" menu; every choice persists via
/// the controllers' shared_preferences backing and rebuilds the whole app. The
/// Language row always shows both languages (English & Kiswahili are never
/// hidden for the sake of "translation completeness").
Future<void> showSettingsSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => const _SettingsSheet(),
  );
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final themeController = ThemeScope.of(context);
    final localeController = LocaleScope.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.tr('profile.appearanceLanguage'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              s.tr('profile.adaptExperience'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const Divider(height: 32),
            Text(
              s.tr('common.theme').toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.blue,
                letterSpacing: .8,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<ThemeMode>(
              segments: [
                for (final (mode, label) in const [
                  (ThemeMode.light, 'settings.themeLight'),
                  (ThemeMode.dark, 'settings.themeDark'),
                  (ThemeMode.system, 'settings.themeSystem'),
                ])
                  ButtonSegment(
                    value: mode,
                    label: Text(s.tr(label)),
                    icon: Icon(
                      switch (mode) {
                        ThemeMode.light => Icons.light_mode_outlined,
                        ThemeMode.dark => Icons.dark_mode_outlined,
                        ThemeMode.system => Icons.brightness_auto_outlined,
                      },
                      size: 16,
                    ),
                  ),
              ],
              selected: {themeController.value},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  themeController.setMode(selection.first),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              s.tr('common.language').toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.blue,
                letterSpacing: .8,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'en',
                  label: Text(s.tr('settings.languageEnglish')),
                ),
                const ButtonSegment(
                  value: 'sw',
                  label: Text('Kiswahili'),
                ),
                ButtonSegment(
                  value: '',
                  label: Text(s.tr('settings.languageDevice')),
                ),
              ],
              selected: {localeController.storedLanguageTag ?? ''},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                final tag = selection.first;
                localeController.setLanguage(tag.isEmpty ? null : tag);
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              s.tr('settings.themeFollowDevice'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}