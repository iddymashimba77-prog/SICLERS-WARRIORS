import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/l10n/locale_controller.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../shared/widgets/app_logo.dart';
import '../../../../core/theme/app_shapes.dart';

/// Public landing page for Sickler's Warriors.
///
/// One integrated hero: the official brand lockup, headline and actions, a
/// glass service-shortcut panel, and the existing signed-in phone mockup as a
/// large companion visual. There is no separate lower section; the page ends
/// inside the hero. News and announcements are deliberately absent.
class PublicHomePage extends StatefulWidget {
  const PublicHomePage({super.key});

  static const String routeName = '/';

  @override
  State<PublicHomePage> createState() => _PublicHomePageState();
}

class _PublicHomePageState extends State<PublicHomePage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 1024;

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: CustomScrollView(
        slivers: [
          _PublicHeader(isDesktop: isDesktop),
          SliverToBoxAdapter(
            child: _PublicHero(
              key: const ValueKey('public-hero'),
              theme: theme,
            ),
          ),
        ],
      ),
    );
  }
}

// ===================================================================== header

/// Persistent SOS affordance in the public header: the crisis path is never
/// more than one tap away, on top of the emergency strip further down.
class _HeaderSosButton extends StatelessWidget {
  const _HeaderSosButton({this.compact = false});

  /// Icon-only on the compact toolbar, where a labelled button would squeeze
  /// the brand mark out of the app bar.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final hint = s.tr('home.sosHint');
    void go() => goTo(context, '/emergency');
    if (compact) {
      return IconButton(
        key: const ValueKey('public-header-sos'),
        tooltip: hint,
        onPressed: go,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.emergency,
          foregroundColor: Colors.white,
          minimumSize: const Size(40, 40),
        ),
        icon: const Icon(Icons.emergency_outlined, size: 20),
      );
    }
    return Tooltip(
      message: hint,
      child: FilledButton.icon(
        key: const ValueKey('public-header-sos'),
        onPressed: go,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.emergency,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm + 2,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppShapes.pill),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        icon: const Icon(Icons.emergency_outlined, size: 18),
        label: Text(s.tr('home.sos')),
      ),
    );
  }
}

class _PublicHeader extends StatelessWidget {
  const _PublicHeader({required this.isDesktop});

  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      backgroundColor: AppColors.navy,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      pinned: true,
      centerTitle: false,
      automaticallyImplyLeading: false,
      toolbarHeight: isDesktop ? 72 : 60,
      leadingWidth: isDesktop ? null : 64,
      leading: isDesktop
          ? null
          : const Padding(
              padding: EdgeInsets.only(left: AppSpacing.lg),
              child: _HeaderSosButton(compact: true),
            ),
      titleSpacing: 0,
      actions: isDesktop
          ? [
              const _HeaderSosButton(),
              const SizedBox(width: AppSpacing.sm),
              const _PublicThemeToggle(),
              const SizedBox(width: AppSpacing.xs),
              const _PublicLanguageToggle(),
              const SizedBox(width: AppSpacing.md),
            ]
          : [
              const _PublicThemeToggle(),
              const SizedBox(width: AppSpacing.xs),
              const _PublicLanguageToggle(),
              const SizedBox(width: AppSpacing.md),
            ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: Colors.white.withValues(alpha: .08),
        ),
      ),
    );
  }
}

class _PublicThemeToggle extends StatelessWidget {
  const _PublicThemeToggle();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.maybeOf(context);
    if (theme == null) return const SizedBox.shrink();
    final s = AppLocalizations.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      key: const ValueKey('public-theme-toggle'),
      tooltip: dark ? s.tr('common.lightMode') : s.tr('common.darkMode'),
      onPressed: () =>
          theme.setMode(dark ? ThemeMode.light : ThemeMode.dark),
      style: IconButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.white.withValues(alpha: .06),
        minimumSize: const Size(40, 40),
      ),
      icon: Icon(
        dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        size: 20,
      ),
    );
  }
}

class _PublicLanguageToggle extends StatelessWidget {
  const _PublicLanguageToggle();

  @override
  Widget build(BuildContext context) {
    final locale = LocaleScope.maybeOf(context);
    if (locale == null) return const SizedBox.shrink();
    final swahili = locale.isSwahili;
    return TextButton(
      key: const ValueKey('public-language-toggle'),
      onPressed: () => locale.setLanguage(swahili ? 'en' : 'sw'),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.white.withValues(alpha: .06),
        minimumSize: const Size(44, 40),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        shape: const RoundedRectangleBorder(borderRadius: AppShapes.pill),
      ),
      child: Text(
        swahili ? 'EN' : 'SW',
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: .4,
        ),
      ),
    );
  }
}

// ====================================================================== hero

class _PublicHero extends StatelessWidget {
  const _PublicHero({super.key, required this.theme});

  final ThemeData theme;

  static const double _maxWidth = AppSpacing.contentMaxWidth;
  static const double _twoColumnBreakpoint = 1100;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final twoColumn = width >= _twoColumnBreakpoint;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, AppColors.navyDeep, AppColors.blue],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          const Positioned(
            top: -180,
            right: -120,
            child: _HeroGlow(
              color: AppColors.blue,
              size: 560,
              opacity: .38,
            ),
          ),
          const Positioned(
            bottom: -220,
            left: -140,
            child: _HeroGlow(
              color: AppColors.emergency,
              size: 460,
              opacity: .14,
            ),
          ),
          const Positioned(
            top: 180,
            left: -220,
            child: _HeroGlow(
              color: AppColors.blue,
              size: 420,
              opacity: .16,
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                twoColumn ? AppSpacing.xxxl : AppSpacing.lg,
                twoColumn ? AppSpacing.xxxl : AppSpacing.xl,
                twoColumn ? AppSpacing.xxxl : AppSpacing.lg,
                AppSpacing.xxxl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (twoColumn)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              flex: 9,
                              child: _HeroContent(isDesktop: true),
                            ),
                            const SizedBox(width: AppSpacing.xxxl),
                            Expanded(
                              flex: 11,
                              child: _IntegratedPhone(
                                key: const ValueKey('hero-phone'),
                                theme: theme,
                                services: _phoneServices(s),
                                desiredScale: 1.28,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _HeroContent(isDesktop: false),
                        SizedBox(
                          height: width < 600
                              ? AppSpacing.xxl
                              : AppSpacing.xxxl,
                        ),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 500),
                            child: _IntegratedPhone(
                              key: const ValueKey('hero-phone'),
                              theme: theme,
                              services: _phoneServices(s),
                            ),
                          ),
                        ),
                      ],
                      SizedBox(
                        height: twoColumn
                            ? AppSpacing.xxxl
                            : AppSpacing.xxl,
                      ),
                      _GlassServicesPanel(
                        key: const ValueKey('hero-services'),
                        services: _homeServices(s),
                        label: s.tr('home.servicesLabel'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroGlow extends StatelessWidget {
  const _HeroGlow({
    required this.color,
    required this.size,
    required this.opacity,
  });

  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
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
      ),
    );
  }
}

class _HeroContent extends StatelessWidget {
  const _HeroContent({required this.isDesktop});

  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final align =
        isDesktop ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final textAlign = isDesktop ? TextAlign.start : TextAlign.center;

    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeroBrandLockup(isDesktop: isDesktop),
        const SizedBox(height: AppSpacing.xxl),
        Container(
          width: 44,
          height: 4,
          decoration: const BoxDecoration(
            color: AppColors.emergency,
            borderRadius: AppShapes.pill,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          s.tr('home.heroTitle'),
          textAlign: textAlign,
          style: TextStyle(
            color: Colors.white,
            fontSize: isDesktop ? 56 : 38,
            fontWeight: FontWeight.w800,
            height: 1.04,
            letterSpacing: isDesktop ? -1.4 : -0.8,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          s.tr('home.heroSubtitle'),
          textAlign: textAlign,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .82),
            fontSize: isDesktop ? 21 : 17,
            fontWeight: FontWeight.w500,
            height: 1.35,
            letterSpacing: .1,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          alignment: isDesktop ? WrapAlignment.start : WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              key: const ValueKey('home-cta-join'),
              onPressed: () => Navigator.pushNamed(context, '/signup'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.emergency,
                foregroundColor: Colors.white,
                elevation: 2,
                shadowColor: AppColors.emergency.withValues(alpha: .55),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md + 2,
                ),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppShapes.medium,
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.groups_2_outlined, size: 19),
              label: Text(s.tr('home.heroPrimaryCta')),
            ),
            OutlinedButton(
              key: const ValueKey('home-cta-login'),
              onPressed: () => Navigator.pushNamed(context, '/login'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: .06),
                side: BorderSide(
                  color: Colors.white.withValues(alpha: .38),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md + 2,
                ),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppShapes.medium,
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(s.tr('common.signIn')),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroBrandLockup extends StatelessWidget {
  const _HeroBrandLockup({required this.isDesktop});

  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final logo = Container(
      key: const ValueKey('hero-logo'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppShapes.card,
        border: Border.all(color: AppColors.blue.withValues(alpha: .18)),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue.withValues(alpha: .35),
            offset: const Offset(0, 12),
            blurRadius: 28,
            spreadRadius: -6,
          ),
        ],
      ),
      child: AppLogo(height: isDesktop ? 56 : 46),
    );
    final wordmark = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          isDesktop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          AppStrings.appName,
          style: TextStyle(
            color: Colors.white,
            fontSize: isDesktop ? 20 : 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -.3,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          s.tr('home.tagline'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: .66),
            fontSize: isDesktop ? 12 : 10.5,
            fontWeight: FontWeight.w500,
            letterSpacing: .8,
          ),
        ),
      ],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        logo,
        const SizedBox(width: AppSpacing.md),
        Flexible(child: wordmark),
      ],
    );
  }
}

class _IntegratedPhone extends StatelessWidget {
  const _IntegratedPhone({
    super.key,
    required this.theme,
    required this.services,
    this.desiredScale = 1,
  });

  final ThemeData theme;
  final List<_ServiceSpec> services;
  final double desiredScale;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final naturalWidth =
            math.max(200.0, math.min(constraints.maxWidth, 500.0));
        final phoneWidth =
            math.max(200.0, math.min(300.0, naturalWidth - 72));
        final naturalHeight = phoneWidth * 2.02 + 48;
        final scale =
            math.min(desiredScale, constraints.maxWidth / naturalWidth);
        return SizedBox(
          width: naturalWidth * scale,
          height: naturalHeight * scale,
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: naturalWidth,
              height: naturalHeight,
              child: _PhoneShowcase(theme: theme, services: services),
            ),
          ),
        );
      },
    );
  }
}

class _HomeService {
  const _HomeService({
    required this.id,
    required this.label,
    required this.icon,
    required this.route,
    this.emergency = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final String route;
  final bool emergency;
}

List<_HomeService> _homeServices(AppLocalizations s) => [
      _HomeService(
        id: 'health',
        label: s.tr('srv.healthTitle'),
        icon: Icons.health_and_safety_outlined,
        route: '/health',
      ),
      _HomeService(
        id: 'hydration',
        label: s.tr('home.serviceHydration'),
        icon: Icons.water_drop_outlined,
        route: '/hydration',
      ),
      _HomeService(
        id: 'blood',
        label: s.tr('srv.bloodTitle'),
        icon: Icons.bloodtype_outlined,
        route: '/blood-donation',
        emergency: true,
      ),
      _HomeService(
        id: 'education',
        label: s.tr('home.serviceEducation'),
        icon: Icons.school_outlined,
        route: '/education',
      ),
      _HomeService(
        id: 'community',
        label: s.tr('home.serviceCommunity'),
        icon: Icons.forum_outlined,
        route: '/community',
      ),
      _HomeService(
        id: 'ai',
        label: s.tr('home.serviceAi'),
        icon: Icons.auto_awesome_outlined,
        route: '/ai-assistant',
      ),
      _HomeService(
        id: 'donate',
        label: s.tr('srv.donateTitle'),
        icon: Icons.volunteer_activism_outlined,
        route: '/donations',
        emergency: true,
      ),
    ];

List<_ServiceSpec> _phoneServices(AppLocalizations s) => [
      _ServiceSpec(
        title: s.tr('srv.healthTitle'),
        icon: Icons.health_and_safety_outlined,
        actions: const [
          _SectionAction(labelKey: 'act.healthDashboard', route: '/health'),
          _SectionAction(labelKey: 'act.manageMedication', route: '/medication'),
        ],
      ),
      _ServiceSpec(
        title: s.tr('srv.doctorTitle'),
        icon: Icons.medical_services_outlined,
        actions: const [
          _SectionAction(labelKey: 'act.findDoctor', route: '/doctors'),
          _SectionAction(labelKey: 'act.visitClinic', route: '/clinic'),
        ],
      ),
      _ServiceSpec(
        title: s.tr('srv.bloodTitle'),
        icon: Icons.bloodtype_outlined,
        emergency: true,
        actions: const [
          _SectionAction(labelKey: 'act.bloodNetwork', route: '/blood-donation'),
          _SectionAction(labelKey: 'act.donateBlood', route: '/donor-home'),
        ],
      ),
      _ServiceSpec(
        title: s.tr('srv.emergencyTitle'),
        icon: Icons.emergency_outlined,
        emergency: true,
        actions: const [
          _SectionAction(labelKey: 'act.emergencySos', route: '/emergency'),
        ],
      ),
      _ServiceSpec(
        title: s.tr('srv.educationTitle'),
        icon: Icons.school_outlined,
        actions: const [
          _SectionAction(labelKey: 'act.openAcademy', route: '/education'),
        ],
      ),
      _ServiceSpec(
        title: s.tr('srv.communityTitle'),
        icon: Icons.forum_outlined,
        actions: const [
          _SectionAction(labelKey: 'act.joinCommunity', route: '/community'),
          _SectionAction(labelKey: 'act.messages', route: '/messages'),
          _SectionAction(labelKey: 'act.aiCoach', route: '/ai-assistant'),
        ],
      ),
      _ServiceSpec(
        title: s.tr('srv.donateTitle'),
        icon: Icons.volunteer_activism_outlined,
        actions: const [
          _SectionAction(labelKey: 'act.makeDonation', route: '/donations'),
          _SectionAction(labelKey: 'act.changiaHub', route: '/changia'),
        ],
      ),
    ];

class _GlassServicesPanel extends StatelessWidget {
  const _GlassServicesPanel({
    super.key,
    required this.services,
    required this.label,
  });

  final List<_HomeService> services;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppShapes.hero,
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: .28),
            offset: const Offset(0, 18),
            blurRadius: 40,
            spreadRadius: -10,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppShapes.hero,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .06),
              borderRadius: AppShapes.hero,
              border: Border.all(color: Colors.white.withValues(alpha: .14)),
            ),
            child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1000
                  ? 7
                  : constraints.maxWidth >= 640
                      ? 4
                      : constraints.maxWidth >= 480
                          ? 3
                          : 2;
              final compact = constraints.maxWidth < 520;
              const gap = AppSpacing.sm;
              final cardWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              final cardHeight = compact ? 58.0 : 112.0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .10),
                          borderRadius: AppShapes.small,
                        ),
                        child: const Icon(
                          Icons.grid_view_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final service in services)
                        SizedBox(
                          width: cardWidth,
                          height: cardHeight,
                          child: _ServiceCard(
                            service: service,
                            compact: compact,
                          ),
                        ),
                    ],
                  ),
                ],
              );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.compact});

  final _HomeService service;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent =
        service.emergency ? AppColors.emergency : AppColors.blue;
    final icon = Container(
      width: compact ? 34 : 38,
      height: compact ? 34 : 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .22),
        borderRadius: AppShapes.small,
        border: Border.all(color: accent.withValues(alpha: .35)),
      ),
      child: Icon(
        service.icon,
        size: compact ? 18 : 20,
        color: Colors.white,
      ),
    );
    final label = Text(
      service.label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontSize: compact ? 12 : 12.5,
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('home-service-${service.id}'),
        borderRadius: AppShapes.card,
        onTap: () => goTo(context, service.route),
        overlayColor: WidgetStatePropertyAll(
          Colors.white.withValues(alpha: .08),
        ),
        child: Container(
          padding: EdgeInsets.all(
            compact ? AppSpacing.md : AppSpacing.md + 2,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .055),
            borderRadius: AppShapes.card,
            border: Border.all(color: Colors.white.withValues(alpha: .13)),
          ),
          child: compact
              ? Row(
                  children: [
                    icon,
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: label),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(height: AppSpacing.sm),
                    label,
                  ],
                ),
        ),
      ),
    );
  }
}

// ==================================================== service area sections

/// One public service area rendered as a quick-action tile in the phone
/// mockup: localized title, icon and priority action routes.
class _ServiceSpec {
  const _ServiceSpec({
    required this.title,
    required this.icon,
    required this.actions,
    this.emergency = false,
  });

  final String title;
  final IconData icon;
  final List<_SectionAction> actions;
  final bool emergency;
}

/// Phone mockup of the signed-in app: status notch, brand app bar, a compact
/// greeting, a 7-tile quick-action grid (every tile routes to its real
/// destination) and a red SOS strip — ringed by six floating healthcare icons
/// that reveal with a short staggered rise. The reveal is finite, so widget
/// tests that settle the page still finish.
///
/// The mockup itself is unchanged from the signed-in app preview; the public
/// hero only scales and positions it as a companion visual.
class _PhoneShowcase extends StatefulWidget {
  const _PhoneShowcase({required this.theme, required this.services});

  final ThemeData theme;
  final List<_ServiceSpec> services;

  @override
  State<_PhoneShowcase> createState() => _PhoneShowcaseState();
}

class _PhoneShowcaseState extends State<_PhoneShowcase>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _reveal.value = 1;
    } else if (!_reveal.isAnimating && !_reveal.isCompleted) {
      _reveal.forward();
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = widget.theme;
    final dark = theme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final colW = constraints.maxWidth;
        final phoneW = math.max(200.0, math.min(300.0, colW - 72));
        final phoneH = phoneW * 2.02;
        final stackH = phoneH + 48;

        const bubbles = <({IconData icon, Color color})>[
          (icon: Icons.health_and_safety_outlined, color: AppColors.blue),
          (icon: Icons.water_drop_outlined, color: AppColors.emergency),
          (icon: Icons.forum_outlined, color: AppColors.blue),
          (icon: Icons.school_outlined, color: AppColors.navy),
          (icon: Icons.favorite, color: AppColors.emergency),
          (icon: Icons.monitor_heart_outlined, color: AppColors.blue),
        ];

        return SizedBox(
          width: colW,
          height: stackH,
          child: ListenableBuilder(
            listenable: _reveal,
            builder: (context, _) {
              Widget bubbleAt(int index) {
                final b = bubbles[index];
                final t = Interval(
                  index * 0.08,
                  math.min(1.0, index * 0.08 + 0.55),
                  curve: Curves.easeOutCubic,
                ).transform(_reveal.value);

                // Two flanking columns of icons, three down each side.
                final leftSide = index.isEven;
                final slot = index ~/ 2;
                final top = slot == 0
                    ? stackH * .07
                    : slot == 1
                        ? stackH * .44
                        : null;
                final bottom = slot == 2 ? 6.0 : null;
                return Positioned(
                  left: leftSide
                      ? (slot == 2 ? colW * .12 : 0.0)
                      : null,
                  right: leftSide
                      ? null
                      : (slot == 2 ? colW * .10 : 0.0),
                  top: top,
                  bottom: bottom,
                  child: Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, (1 - t) * 20),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.navy.withValues(alpha: .18),
                              offset: const Offset(0, 8),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                        child: Icon(b.icon, size: 21, color: b.color),
                      ),
                    ),
                  ),
                );
              }

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 24,
                    left: (colW - phoneW) / 2,
                    width: phoneW,
                    height: phoneH,
                    child: _phone(context, s, dark),
                  ),
                  for (var i = 0; i < bubbles.length; i++) bubbleAt(i),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _phone(
    BuildContext context,
    AppLocalizations s,
    bool dark,
  ) {
    final theme = widget.theme;
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: AppShapes.hero,
        border: Border.all(color: AppColors.dividerOnDark),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: dark ? .45 : .28),
            offset: const Offset(0, 24),
            blurRadius: 40,
            spreadRadius: -10,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppShapes.card,
        child: ColoredBox(
          color: dark ? AppColors.navyDeep : AppColors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 22,
                color: AppColors.navy,
                alignment: Alignment.center,
                child: Container(
                  width: 56,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .45),
                    borderRadius: AppShapes.pill,
                  ),
                ),
              ),
              Container(
                color: AppColors.navy,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  0,
                  AppSpacing.sm,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    const AppLogo(height: 16),
                    const SizedBox(width: AppSpacing.xs),
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
                        color: AppColors.emergency,
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
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          s.tr('home.phoneSubtitle'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          s.tr('home.phoneQuickActions'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .6,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (var start = 0;
                            start < widget.services.length;
                            start += 3)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Row(
                              children: [
                                for (var j = start;
                                    j <
                                        math.min(
                                          start + 3,
                                          widget.services.length,
                                        );
                                    j++) ...[
                                  if (j > start)
                                    const SizedBox(width: AppSpacing.sm),
                                  Expanded(child: _phoneTile(context, widget.services[j])),
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

  Widget _phoneTile(BuildContext context, _ServiceSpec spec) {
    final dark = widget.theme.brightness == Brightness.dark;
    final accent = spec.emergency ? AppColors.emergency : AppColors.blue;
    return Material(
      color: dark
          ? Colors.white.withValues(alpha: .06)
          : widget.theme.colorScheme.primaryContainer.withValues(alpha: 0.36),
      shape: RoundedRectangleBorder(
        borderRadius: AppShapes.small,
        side: BorderSide(
          color: dark
              ? AppColors.dividerOnDark
              : AppColors.blue.withValues(alpha: .16),
        ),
      ),
      child: InkWell(
        borderRadius: AppShapes.small,
        onTap: () => goTo(context, spec.actions.first.route),
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
                style: widget.theme.textTheme.bodySmall?.copyWith(
                  fontSize: 9.5,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: widget.theme.colorScheme.onSurface,
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
      color: AppColors.emergency,
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
                color: AppColors.textOnEmergency,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  s.tr('act.emergencySos'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textOnEmergency,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 16,
                color: AppColors.textOnEmergency,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionAction {
  const _SectionAction({required this.labelKey, required this.route});

  final String labelKey;
  final String route;
}

