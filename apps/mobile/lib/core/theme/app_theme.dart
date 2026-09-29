import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_shapes.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Sickler's Warriors — global theme (FRONTEND-1).
///
/// Everything reads from the centralized tokens ([AppColors], [AppTypography],
/// [AppShapes], [AppSpacing]). Feature widgets must use `Theme.of(context)`
/// instead of scattering literals so dark mode can be layered on later.
class AppTheme {
  AppTheme._();

  static ColorScheme colorScheme(BuildContext context) =>
      Theme.of(context).colorScheme;

  // ------------------------------------------------------------------- light
  static final ThemeData light = _build(
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: AppColors.blue,
      onPrimary: AppColors.textOnBlue,
      primaryContainer: Color(0xFFE6EFFA),
      onPrimaryContainer: AppColors.navy,
      secondary: AppColors.blue,
      onSecondary: AppColors.textOnBlue,
      secondaryContainer: Color(0xFFE6EFFA),
      onSecondaryContainer: AppColors.navy,
      tertiary: AppColors.navy,
      onTertiary: AppColors.textOnDark,
      tertiaryContainer: Color(0xFFE2E8F2),
      onTertiaryContainer: AppColors.navy,
      error: AppColors.emergency,
      onError: AppColors.textOnEmergency,
      errorContainer: AppColors.emergencyContainer,
      onErrorContainer: AppColors.emergency,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: AppColors.surface,
      surfaceContainerLow: AppColors.surfaceMuted,
      surfaceContainer: Color(0xFFF1F4F9),
      surfaceContainerHigh: Color(0xFFEBEFF5),
      surfaceContainerHighest: Color(0xFFE3E8F0),
      outline: AppColors.border,
      outlineVariant: AppColors.borderSubtle,
      inverseSurface: AppColors.navy,
      onInverseSurface: AppColors.textOnDark,
      inversePrimary: Color(0xFFBBD4F5),
      shadow: Color(0xFF0B1F3D),
      scrim: Color(0x660B1F3D),
      surfaceTint: Colors.transparent,
    ),
  );

  // -------------------------------------------------------------------- dark
  static final ThemeData dark = _build(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF8FBCF0),
      onPrimary: AppColors.navy,
      primaryContainer: Color(0xFF1C3A63),
      onPrimaryContainer: Color(0xFFCDE0F5),
      secondary: Color(0xFF8FBCF0),
      onSecondary: AppColors.navy,
      secondaryContainer: Color(0xFF1C3A63),
      onSecondaryContainer: Color(0xFFCDE0F5),
      tertiary: Color(0xFFB6C3D8),
      onTertiary: AppColors.navy,
      tertiaryContainer: Color(0xFF2A3550),
      onTertiaryContainer: Color(0xFFD5DEEA),
      error: Color(0xFFFF8A9E),
      onError: AppColors.navy,
      errorContainer: Color(0xFF4A1520),
      onErrorContainer: Color(0xFFFFC4CE),
      surface: Color(0xFF0D1626),
      onSurface: Color(0xFFE6EDF6),
      onSurfaceVariant: Color(0xFF9FB0C5),
      surfaceContainerLowest: Color(0xFF0A111E),
      surfaceContainerLow: Color(0xFF111C2F),
      surfaceContainer: Color(0xFF16223A),
      surfaceContainerHigh: Color(0xFF1B2945),
      surfaceContainerHighest: Color(0xFF213150),
      outline: Color(0xFF33455F),
      outlineVariant: Color(0xFF26364E),
      inverseSurface: Color(0xFFE6EDF6),
      onInverseSurface: AppColors.navy,
      inversePrimary: AppColors.blue,
      shadow: Color(0x00000000),
      scrim: Color(0xCC000000),
      surfaceTint: Colors.transparent,
    ),
  );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme colorScheme,
  }) {
    final bool isDark = brightness == Brightness.dark;
    final Color surface = colorScheme.surface;
    final Color appBarBg = isDark ? const Color(0xFF0E1626) : AppColors.navy;
    final Color border = colorScheme.outlineVariant;

    final InputDecorationTheme inputTheme = InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md + 2,
      ),
      prefixIconColor: colorScheme.onSurfaceVariant,
      suffixIconColor: colorScheme.onSurfaceVariant,
      labelStyle: AppTypography.label.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
      hintStyle: AppTypography.bodySmall.copyWith(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      errorStyle: const TextStyle(color: AppColors.emergency, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: AppShapes.medium,
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppShapes.medium,
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppShapes.medium,
        borderSide: const BorderSide(color: AppColors.blue, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppShapes.medium,
        borderSide: const BorderSide(color: AppColors.emergency, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: AppShapes.medium,
        borderSide: const BorderSide(color: AppColors.emergency, width: 1.6),
      ),
    );

    final ButtonStyle filledButton = FilledButton.styleFrom(
      minimumSize: const Size(64, 48),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      disabledBackgroundColor: colorScheme.onSurface.withValues(alpha: 0.12),
      disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
      shape: RoundedRectangleBorder(borderRadius: AppShapes.medium),
      textStyle: AppTypography.button.copyWith(color: colorScheme.onPrimary),
      elevation: 0,
    );

    final ButtonStyle elevatedButton = ElevatedButton.styleFrom(
      minimumSize: const Size(64, 48),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: AppShapes.medium),
      textStyle: AppTypography.button.copyWith(color: colorScheme.onPrimary),
    );

    final ButtonStyle outlinedButton = OutlinedButton.styleFrom(
      minimumSize: const Size(64, 48),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      foregroundColor: isDark ? colorScheme.primary : AppColors.navy,
      side: BorderSide(color: AppColors.blue.withValues(alpha: 0.45)),
      shape: RoundedRectangleBorder(borderRadius: AppShapes.medium),
      textStyle: AppTypography.button.copyWith(
        color: isDark ? colorScheme.primary : AppColors.navy,
      ),
    );

    final ButtonStyle textButton = TextButton.styleFrom(
      minimumSize: const Size(48, 44),
      foregroundColor: isDark ? colorScheme.primary : AppColors.blue,
      shape: RoundedRectangleBorder(borderRadius: AppShapes.small),
      textStyle: AppTypography.button.copyWith(
        color: isDark ? colorScheme.primary : AppColors.blue,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isDark ? colorScheme.surface : AppColors.background,
      textTheme: AppTypography.textTheme(brightness: brightness),
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBg,
        foregroundColor: AppColors.textOnDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
        titleSpacing: AppSpacing.lg,
        titleTextStyle: AppTypography.title.copyWith(color: AppColors.textOnDark),
        iconTheme: IconThemeData(color: AppColors.textOnDark),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: surface,
        elevation: 0,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppTypography.label.copyWith(color: colorScheme.primary)
              : AppTypography.label.copyWith(
                  color: colorScheme.onSurfaceVariant,
                );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        useIndicator: true,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        selectedIconTheme: IconThemeData(color: colorScheme.primary),
        unselectedIconTheme: IconThemeData(
          color: colorScheme.onSurfaceVariant,
        ),
        selectedLabelTextStyle: AppTypography.label.copyWith(
          color: colorScheme.primary,
        ),
        unselectedLabelTextStyle: AppTypography.label.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      inputDecorationTheme: inputTheme,
      filledButtonTheme: FilledButtonThemeData(style: filledButton),
      elevatedButtonTheme: ElevatedButtonThemeData(style: elevatedButton),
      outlinedButtonTheme: OutlinedButtonThemeData(style: outlinedButton),
      textButtonTheme: TextButtonThemeData(style: textButton),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: AppShapes.small),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.card,
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? colorScheme.outlineVariant : AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        selectedColor: colorScheme.secondaryContainer,
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: AppShapes.small),
        labelStyle: AppTypography.label,
        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
        circularTrackColor: colorScheme.surfaceContainerHighest,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppShapes.large),
        titleTextStyle: AppTypography.title.copyWith(color: colorScheme.onSurface),
        contentTextStyle: AppTypography.body.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppShapes.bottomSheetTop),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.navy,
        contentTextStyle: const TextStyle(color: AppColors.textOnDark, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppShapes.medium),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.onPrimary
              : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.primary
              : Colors.transparent,
        ),
        side: BorderSide(color: colorScheme.outline, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: AppShapes.small),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: AppShapes.small,
        ),
        textStyle: const TextStyle(color: AppColors.textOnDark, fontSize: 13),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(surface),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: AppShapes.medium,
              side: BorderSide(color: border),
            ),
          ),
        ),
      ),
    );
  }
}