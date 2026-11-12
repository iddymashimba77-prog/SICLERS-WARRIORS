import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/l10n/locale_controller.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme_controller.dart';

class PublicHomePage extends StatelessWidget {
  const PublicHomePage({super.key});

  static const String routeName = '/';

  @override
  Widget build(BuildContext context) {
    final mode = ThemeScope.maybeOf(context)?.value ?? ThemeMode.system;
    final dark = mode != ThemeMode.light;
    final palette = _HomePalette.of(dark);

    return Scaffold(
      backgroundColor: palette.background.first,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: palette.background,
            stops: const [0, .55, 1],
          ),
        ),
        child: ClipRect(
          child: SingleChildScrollView(
            child: Stack(
              children: [
                Positioned.fill(child: _HomeBackground(palette: palette)),
                SafeArea(
                  bottom: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg + 4,
                              AppSpacing.xs,
                              AppSpacing.lg + 4,
                              0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _TopBar(palette: palette),
                                const SizedBox(height: AppSpacing.md + 2),
                                _Hero(palette: palette),
                                const SizedBox(height: AppSpacing.md + 2),
                                _ServiceMenu(palette: palette),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: _PhoneStage(palette: palette),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomePalette {
  const _HomePalette({
    required this.dark,
    required this.background,
    required this.glowBlue,
    required this.glowRed,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.glassFill,
    required this.glassBorder,
    required this.glassShadow,
    required this.tileFill,
    required this.tileHover,
    required this.tileBorder,
    required this.tileBorderHover,
    required this.controlFill,
    required this.controlBorder,
    required this.divider,
    required this.phoneFrame,
    required this.phoneScreen,
    required this.phoneText,
    required this.phoneMuted,
    required this.phoneTileFill,
    required this.phoneTileBorder,
    required this.swooshInner,
    required this.loginBorder,
    required this.loginText,
    required this.wordmarkSickle,
    required this.wordmarkWarriors,
    required this.taglinePrimary,
    required this.taglineSecondary,
  });

  final bool dark;
  final List<Color> background;
  final Color glowBlue;
  final Color glowRed;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color glassFill;
  final Color glassBorder;
  final Color glassShadow;
  final Color tileFill;
  final Color tileHover;
  final Color tileBorder;
  final Color tileBorderHover;
  final Color controlFill;
  final Color controlBorder;
  final Color divider;
  final Color phoneFrame;
  final Color phoneScreen;
  final Color phoneText;
  final Color phoneMuted;
  final Color phoneTileFill;
  final Color phoneTileBorder;
  final Color swooshInner;
  final Color loginBorder;
  final Color loginText;
  final Color wordmarkSickle;
  final Color wordmarkWarriors;
  final Color taglinePrimary;
  final Color taglineSecondary;

  factory _HomePalette.of(bool dark) {
    if (dark) {
      return _HomePalette(
        dark: true,
        background: const [
          AppColors.homeNavyTop,
          AppColors.homeNavyMid,
          AppColors.homeBlueBottom,
        ],
        glowBlue: AppColors.homeAccentBlue,
        glowRed: AppColors.homeRed,
        textPrimary: Colors.white,
        textSecondary: AppColors.homeLavender,
        textMuted: Colors.white.withValues(alpha: .70),
        glassFill: Colors.white.withValues(alpha: .08),
        glassBorder: Colors.white.withValues(alpha: .18),
        glassShadow: AppColors.homeNavyTop.withValues(alpha: .38),
        tileFill: Colors.white.withValues(alpha: .06),
        tileHover: Colors.white.withValues(alpha: .12),
        tileBorder: Colors.white.withValues(alpha: .14),
        tileBorderHover: Colors.white.withValues(alpha: .30),
        controlFill: Colors.white.withValues(alpha: .06),
        controlBorder: Colors.white.withValues(alpha: .55),
        divider: Colors.white.withValues(alpha: .18),
        phoneFrame: AppColors.homeNavyTop,
        phoneScreen: AppColors.homePhoneScreen,
        phoneText: Colors.white,
        phoneMuted: AppColors.homeLavender,
        phoneTileFill: Colors.white.withValues(alpha: .09),
        phoneTileBorder: Colors.white.withValues(alpha: .16),
        swooshInner: Colors.white,
        loginBorder: Colors.white.withValues(alpha: .55),
        loginText: Colors.white,
        wordmarkSickle: Colors.white,
        wordmarkWarriors: Colors.white,
        taglinePrimary: AppColors.homeLavender,
        taglineSecondary: Colors.white,
      );
    }
    return _HomePalette(
      dark: false,
      background: const [
        AppColors.homeLightTop,
        AppColors.homeLightMid,
        AppColors.homeLightBottom,
      ],
      glowBlue: AppColors.homeAccentBlue,
      glowRed: AppColors.homeRed,
      textPrimary: AppColors.homeInk,
      textSecondary: AppColors.homeInkMuted,
      textMuted: AppColors.homeInkMuted,
      glassFill: Colors.white.withValues(alpha: .62),
      glassBorder: AppColors.navy.withValues(alpha: .10),
      glassShadow: AppColors.navy.withValues(alpha: .12),
      tileFill: Colors.white.withValues(alpha: .72),
      tileHover: Colors.white.withValues(alpha: .94),
      tileBorder: AppColors.navy.withValues(alpha: .10),
      tileBorderHover: AppColors.homeBlueBottom.withValues(alpha: .34),
      controlFill: Colors.white.withValues(alpha: .55),
      controlBorder: AppColors.navy.withValues(alpha: .35),
      divider: AppColors.navy.withValues(alpha: .12),
      phoneFrame: AppColors.homeInk,
      phoneScreen: AppColors.surface,
      phoneText: AppColors.homeInk,
      phoneMuted: AppColors.homeInkMuted,
      phoneTileFill: AppColors.surface,
      phoneTileBorder: AppColors.borderSubtle,
      swooshInner: Colors.white,
      loginBorder: AppColors.navy.withValues(alpha: .35),
      loginText: AppColors.homeInk,
      wordmarkSickle: AppColors.homeInk,
      wordmarkWarriors: AppColors.homeInk,
      taglinePrimary: AppColors.homeBlueBottom,
      taglineSecondary: AppColors.homeInk,
    );
  }
}

class _HomeBackground extends StatelessWidget {
  const _HomeBackground({required this.palette});

  final _HomePalette palette;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            top: -100,
            left: -100,
            child: _HomeGlow(
              color: palette.glowBlue,
              size: 560,
              opacity: palette.dark ? .26 : .16,
            ),
          ),
          Positioned(
            top: -60,
            right: -140,
            child: _HomeGlow(
              color: palette.glowBlue,
              size: 520,
              opacity: palette.dark ? .42 : .22,
            ),
          ),
          Positioned(
            top: 360,
            left: -190,
            child: _HomeGlow(
              color: palette.glowBlue,
              size: 400,
              opacity: .12,
            ),
          ),
          Positioned(
            top: 360,
            right: -160,
            child: _HomeGlow(
              color: palette.glowBlue,
              size: 440,
              opacity: palette.dark ? .16 : .10,
            ),
          ),
          Positioned(
            bottom: -120,
            left: -110,
            child: _HomeGlow(
              color: palette.glowRed,
              size: 380,
              opacity: palette.dark ? .12 : .09,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeGlow extends StatelessWidget {
  const _HomeGlow({
    required this.color,
    required this.size,
    required this.opacity,
  });

  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.palette});

  final _HomePalette palette;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = ThemeScope.maybeOf(context);
    final locale = LocaleScope.maybeOf(context);

    return Row(
      key: const ValueKey('public-top-bar'),
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _SosPill(palette: palette),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            key: const ValueKey('public-theme-toggle'),
            tooltip:
                palette.dark ? s.tr('common.lightMode') : s.tr('common.darkMode'),
            onPressed:
                theme == null
                    ? null
                    : () => theme.setMode(
                      palette.dark ? ThemeMode.light : ThemeMode.dark,
                    ),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              palette.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              size: 20,
              color: palette.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        if (locale != null)
          _LanguagePill(palette: palette, locale: locale),
      ],
    );
  }
}

class _SosPill extends StatelessWidget {
  const _SosPill({required this.palette});

  final _HomePalette palette;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Tooltip(
      message: s.tr('home.sosHint'),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.homeRed, AppColors.homeRedDeep],
            ),
            borderRadius: AppShapes.pill,
            boxShadow: [
              BoxShadow(
                color: AppColors.homeRed.withValues(alpha: .35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: InkWell(
            key: const ValueKey('public-header-sos'),
            borderRadius: AppShapes.pill,
            onTap: () => goTo(context, '/emergency'),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm + 2,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.phone_in_talk_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    s.tr('home.sos'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguagePill extends StatelessWidget {
  const _LanguagePill({required this.palette, required this.locale});

  final _HomePalette palette;
  final LocaleController locale;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Tooltip(
      message: s.tr('common.language'),
      child: OutlinedButton(
        key: const ValueKey('public-language-toggle'),
        onPressed: () => locale.setLanguage(locale.isSwahili ? 'en' : 'sw'),
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          backgroundColor: palette.controlFill,
          side: BorderSide(color: palette.controlBorder, width: 1.5),
          shape: const RoundedRectangleBorder(borderRadius: AppShapes.pill),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 2,
            vertical: AppSpacing.xs,
          ),
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: .3,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.language_rounded, size: 14, color: palette.textPrimary),
            const SizedBox(width: AppSpacing.xs),
            Text(locale.isSwahili ? 'SW' : 'EN'),
            const SizedBox(width: AppSpacing.xxs),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: palette.textPrimary,
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.palette});

  final _HomePalette palette;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Column(
      key: const ValueKey('public-hero'),
      children: [
        _BrandMark(palette: palette),
        const SizedBox(height: AppSpacing.xxs),
        _Wordmark(palette: palette),
        const SizedBox(height: AppSpacing.xs),
        Text(
          s.tr('home.heroTitle'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.taglinePrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.2,
            letterSpacing: -.1,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          s.tr('home.heroSubtitle'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.taglineSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.2,
            letterSpacing: .1,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _HeroActions(palette: palette),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.palette});

  final _HomePalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('hero-logo'),
      width: 132,
      height: 84,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 132,
            height: 84,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  palette.glowBlue.withValues(
                    alpha: palette.dark ? .26 : .16,
                  ),
                  palette.glowBlue.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          Image.asset(
            'assets/brand/sicklers_warriors_logo_transparent.png',
            height: 84,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.palette});

  final _HomePalette palette;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final titleSize = constraints.maxWidth >= 430 ? 40.0 : 34.0;
        return Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    s.tr('home.wordmarkSickle'),
                    style: TextStyle(
                      color: palette.wordmarkSickle,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.8,
                      height: .92,
                    ),
                  ),
                  Text(
                    s.tr('home.wordmarkCell'),
                    style: TextStyle(
                      color: AppColors.homeRed,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.8,
                      height: .92,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Row(
              children: [
                Expanded(
                  child: Container(height: 1, color: palette.divider),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: Text(
                    s.tr('home.wordmarkWarriors'),
                    style: TextStyle(
                      color: palette.wordmarkWarriors,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4.5,
                      height: 1.1,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(height: 1, color: palette.divider),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _HeroActions extends StatelessWidget {
  const _HeroActions({required this.palette});

  final _HomePalette palette;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: _GradientPillButton(
                key: const ValueKey('home-cta-join'),
                label: s.tr('home.heroPrimaryCta'),
                icon: Icons.person_add_alt_1_rounded,
                onPressed: () => Navigator.pushNamed(context, '/signup'),
              ),
            ),
            const SizedBox(width: AppSpacing.md + 3),
            Expanded(
              flex: 1,
              child: OutlinedButton.icon(
                key: const ValueKey('home-cta-login'),
                onPressed: () => Navigator.pushNamed(context, '/login'),
                icon: const Icon(Icons.login_rounded, size: 15),
                label: Text(
                  s.tr('common.signIn'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.loginText,
                  backgroundColor:
                      palette.dark
                          ? Colors.white.withValues(alpha: .04)
                          : Colors.white.withValues(alpha: .55),
                  side: BorderSide(color: palette.loginBorder, width: 1.5),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppShapes.pill,
                  ),
                  minimumSize: const Size.fromHeight(40),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientPillButton extends StatelessWidget {
  const _GradientPillButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.homeRed, AppColors.homeRedDeep],
          ),
          borderRadius: AppShapes.pill,
          boxShadow: [
            BoxShadow(
              color: AppColors.homeRed.withValues(alpha: .35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: AppShapes.pill,
          onTap: onPressed,
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 15, color: Colors.white),
                  const SizedBox(width: AppSpacing.xs + 2),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeService {
  const _HomeService({
    required this.id,
    required this.labelKey,
    required this.icon,
    required this.route,
    required this.accent,
    this.badge,
    this.healthIcon = false,
  });

  final String id;
  final String labelKey;
  final IconData icon;
  final String route;
  final Color accent;
  final String? badge;
  final bool healthIcon;
}

const List<_HomeService> _homeServices = [
  _HomeService(
    id: 'health',
    labelKey: 'srv.healthTitle',
    icon: Icons.favorite_rounded,
    route: '/health',
    accent: AppColors.homeRed,
    healthIcon: true,
  ),
  _HomeService(
    id: 'hydration',
    labelKey: 'home.serviceHydration',
    icon: Icons.water_drop_rounded,
    route: '/hydration',
    accent: AppColors.homeAccentBlue,
  ),
  _HomeService(
    id: 'blood',
    labelKey: 'srv.bloodTitle',
    icon: Icons.bloodtype_rounded,
    route: '/blood-donation',
    accent: AppColors.homeRed,
  ),
  _HomeService(
    id: 'education',
    labelKey: 'srv.educationTitle',
    icon: Icons.school_rounded,
    route: '/education',
    accent: AppColors.homeAccentBlue,
  ),
  _HomeService(
    id: 'community',
    labelKey: 'srv.communityTitle',
    icon: Icons.groups_rounded,
    route: '/community',
    accent: AppColors.homeRed,
    badge: '5',
  ),
  _HomeService(
    id: 'ai',
    labelKey: 'home.serviceAi',
    icon: Icons.smart_toy_rounded,
    route: '/ai-assistant',
    accent: AppColors.homeAccentBlue,
  ),
];

class _ServiceMenu extends StatelessWidget {
  const _ServiceMenu({required this.palette});

  final _HomePalette palette;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Container(
      key: const ValueKey('hero-services'),
      decoration: BoxDecoration(
        borderRadius: AppShapes.homeCard,
        boxShadow: [
          BoxShadow(
            color: palette.glassShadow,
            blurRadius: 36,
            offset: const Offset(0, 18),
            spreadRadius: -12,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppShapes.homeCard,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm + 2),
            decoration: BoxDecoration(
              color: palette.glassFill,
              borderRadius: AppShapes.homeCard,
              border: Border.all(color: palette.glassBorder),
            ),
            child: Semantics(
              label: s.tr('home.servicesLabel'),
              container: true,
              child: Column(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = AppSpacing.sm;
                      final tileWidth =
                          (constraints.maxWidth - gap * 2) / 3;
                      final tileHeight =
                          math.max(76.0, math.min(96.0, tileWidth * .78));
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final service in _homeServices)
                            SizedBox(
                              width: tileWidth,
                              height: tileHeight,
                              child: _HomeTile(
                                palette: palette,
                                service: service,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _DonateRow(palette: palette),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeTile extends StatefulWidget {
  const _HomeTile({required this.palette, required this.service});

  final _HomePalette palette;
  final _HomeService service;

  @override
  State<_HomeTile> createState() => _HomeTileState();
}

class _HomeTileState extends State<_HomeTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final palette = widget.palette;
    final service = widget.service;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 160);

    final icon =
        service.healthIcon
            ? Stack(
              alignment: Alignment.center,
              children: [
                Icon(service.icon, size: 26, color: service.accent),
                const Icon(
                  Icons.monitor_heart_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ],
            )
            : Icon(service.icon, size: 24, color: service.accent);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered && !reduceMotion ? 1.025 : 1,
        duration: duration,
        curve: Curves.easeOut,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('home-service-${service.id}'),
            borderRadius: AppShapes.homeTile,
            onTap: () => goTo(context, service.route),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: duration,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs + 2,
                      vertical: AppSpacing.xs + 2,
                    ),
                    decoration: BoxDecoration(
                      color: _hovered ? palette.tileHover : palette.tileFill,
                      borderRadius: AppShapes.homeTile,
                      border: Border.all(
                        color:
                            _hovered
                                ? palette.tileBorderHover
                                : palette.tileBorder,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: service.accent.withValues(
                              alpha: palette.dark ? .16 : .12,
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: service.accent.withValues(
                                alpha: palette.dark ? .28 : .20,
                              ),
                            ),
                          ),
                          child: icon,
                        ),
                        const SizedBox(height: AppSpacing.xs + 2),
                        Text(
                          s.tr(service.labelKey),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (service.badge != null)
                  Positioned(
                    top: AppSpacing.xs,
                    right: AppSpacing.xs,
                    child: Container(
                      width: 16,
                      height: 16,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.homeRed,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              palette.dark
                                  ? AppColors.homeNavyMid
                                  : Colors.white,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        service.badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DonateRow extends StatefulWidget {
  const _DonateRow({required this.palette});

  final _HomePalette palette;

  @override
  State<_DonateRow> createState() => _DonateRowState();
}

class _DonateRowState extends State<_DonateRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final palette = widget.palette;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 160);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered && !reduceMotion ? 1.015 : 1,
        duration: duration,
        curve: Curves.easeOut,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('home-donate'),
            borderRadius: AppShapes.homeTile,
            onTap: () => goTo(context, '/donations'),
            child: AnimatedContainer(
              duration: duration,
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2),
              decoration: BoxDecoration(
                color: _hovered ? palette.tileHover : palette.tileFill,
                borderRadius: AppShapes.homeTile,
                border: Border.all(
                  color:
                      _hovered ? palette.tileBorderHover : palette.tileBorder,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.volunteer_activism_rounded,
                    size: 20,
                    color: palette.textPrimary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(width: 1, height: 20, color: palette.divider),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      s.tr('srv.donateTitle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: palette.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneStage extends StatelessWidget {
  const _PhoneStage({required this.palette});

  final _HomePalette palette;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final services = _phoneServices(s);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stageWidth = constraints.maxWidth;
        final phoneWidth =
            math.min(340.0, math.max(280.0, stageWidth * .86));
        final phoneHeight = phoneWidth * 2.02 + 12;
        return ClipRect(
          child: SizedBox(
            key: const ValueKey('hero-phone'),
            height: 360,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SwooshPainter(palette: palette),
                  ),
                ),
                Positioned(
                  top: 2,
                  left: stageWidth - phoneWidth + 88,
                  width: phoneWidth,
                  height: phoneHeight,
                  child: Transform(
                    key: const ValueKey('hero-phone-tilt'),
                    alignment: Alignment.topCenter,
                    transform:
                        Matrix4.identity()
                          ..setEntry(3, 2, .0014)
                          ..rotateZ(-14 * math.pi / 180)
                          ..rotateX(.04),
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: _ExistingPhoneMockup(
                          services: services,
                          palette: palette,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PhoneServiceSpec {
  const _PhoneServiceSpec({
    required this.title,
    required this.icon,
    required this.route,
    this.emergency = false,
  });

  final String title;
  final IconData icon;
  final String route;
  final bool emergency;
}

List<_PhoneServiceSpec> _phoneServices(AppLocalizations s) => [
  _PhoneServiceSpec(
    title: s.tr('srv.healthTitle'),
    icon: Icons.health_and_safety_outlined,
    route: '/health',
  ),
  _PhoneServiceSpec(
    title: s.tr('srv.doctorTitle'),
    icon: Icons.medical_services_outlined,
    route: '/doctors',
  ),
  _PhoneServiceSpec(
    title: s.tr('srv.bloodTitle'),
    icon: Icons.bloodtype_outlined,
    route: '/blood-donation',
    emergency: true,
  ),
  _PhoneServiceSpec(
    title: s.tr('srv.emergencyTitle'),
    icon: Icons.emergency_outlined,
    route: '/emergency',
    emergency: true,
  ),
  _PhoneServiceSpec(
    title: s.tr('srv.educationTitle'),
    icon: Icons.school_outlined,
    route: '/education',
  ),
  _PhoneServiceSpec(
    title: s.tr('srv.communityTitle'),
    icon: Icons.forum_outlined,
    route: '/community',
  ),
  _PhoneServiceSpec(
    title: s.tr('srv.donateTitle'),
    icon: Icons.volunteer_activism_outlined,
    route: '/donations',
  ),
];

class _ExistingPhoneMockup extends StatelessWidget {
  const _ExistingPhoneMockup({required this.services, required this.palette});

  final List<_PhoneServiceSpec> services;
  final _HomePalette palette;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final phoneTheme = ThemeData(
      useMaterial3: true,
      brightness: palette.dark ? Brightness.dark : Brightness.light,
    );

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: palette.phoneFrame,
        borderRadius: AppShapes.homePhone,
        border: Border.all(color: Colors.white.withValues(alpha: .16)),
        boxShadow: [
          BoxShadow(
            color: AppColors.homeNavyTop.withValues(alpha: .55),
            offset: const Offset(0, 28),
            blurRadius: 50,
            spreadRadius: -12,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppShapes.homeCard,
        child: ColoredBox(
          color: palette.phoneScreen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 24,
                color: palette.phoneFrame,
                alignment: Alignment.center,
                child: Container(
                  width: 58,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .45),
                    borderRadius: AppShapes.pill,
                  ),
                ),
              ),
              Container(
                color: palette.phoneFrame,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm + 2,
                  0,
                  AppSpacing.sm + 2,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/brand/sicklers_warriors_logo_transparent.png',
                      height: 18,
                      filterQuality: FilterQuality.high,
                    ),
                    const SizedBox(width: AppSpacing.xs + 2),
                    Expanded(
                      child: Text(
                        AppStrings.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: AppColors.homeRed,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.emergency_outlined,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.greeting,
                          style: phoneTheme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: palette.phoneText,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          s.tr('home.phoneSubtitle'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: phoneTheme.textTheme.bodySmall?.copyWith(
                            color: palette.phoneMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          s.tr('home.phoneQuickActions'),
                          style: phoneTheme.textTheme.labelSmall?.copyWith(
                            color: palette.phoneMuted,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .6,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (var start = 0;
                            start < services.length;
                            start += 3)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: Row(
                              children: [
                                for (var j = start;
                                    j < math.min(start + 3, services.length);
                                    j++) ...[
                                  if (j > start)
                                    const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: _phoneTile(
                                      context,
                                      phoneTheme,
                                      services[j],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        const SizedBox(height: AppSpacing.xxs),
                        _phoneSos(context, s),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _phoneTile(
    BuildContext context,
    ThemeData theme,
    _PhoneServiceSpec spec,
  ) {
    final accent = spec.emergency ? AppColors.homeRed : AppColors.homeAccentBlue;
    return Material(
      color: palette.phoneTileFill,
      shape: RoundedRectangleBorder(
        borderRadius: AppShapes.small,
        side: BorderSide(color: palette.phoneTileBorder),
      ),
      child: InkWell(
        borderRadius: AppShapes.small,
        onTap: () => goTo(context, spec.route),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(spec.icon, size: 17, color: accent),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                spec.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 9.5,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: palette.phoneText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _phoneSos(BuildContext context, AppLocalizations s) {
    return Material(
      color: AppColors.homeRed,
      shape: RoundedRectangleBorder(borderRadius: AppShapes.small),
      child: InkWell(
        borderRadius: AppShapes.small,
        onTap: () => goTo(context, '/emergency'),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs + 2,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.emergency_outlined,
                size: 15,
                color: Colors.white,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  s.tr('act.emergencySos'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, size: 16, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwooshPainter extends CustomPainter {
  const _SwooshPainter({required this.palette});

  final _HomePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final path =
        Path()
          ..moveTo(-size.width * .12, size.height * .72)
          ..cubicTo(
            size.width * .16,
            size.height * .22,
            size.width * .40,
            size.height * .92,
            size.width * 1.05,
            size.height * .26,
          );
    final deep =
        Paint()
          ..color = AppColors.homeRedDeep
          ..style = PaintingStyle.stroke
          ..strokeWidth = 58
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final red =
        Paint()
          ..color = AppColors.homeRed
          ..style = PaintingStyle.stroke
          ..strokeWidth = 54
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final inner =
        Paint()
          ..color = palette.swooshInner
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, deep);
    canvas.drawPath(path, red);
    canvas.drawPath(path, inner);
  }

  @override
  bool shouldRepaint(covariant _SwooshPainter oldDelegate) => false;
}
