import 'dart:math' as math;

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

/// Public landing page for Sickler's Warriors (FINALIZE public home).
///
/// A public brand experience built around a calm, premium care journey:
/// a minimal pinned header, an editorial hero, and the signed-in app showcase
/// as the final surface. News and announcements are deliberately absent from
/// the public page.
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
    final s = AppLocalizations.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 1024;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          _PublicHeader(isDesktop: isDesktop),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeroSection(isDesktop: isDesktop, theme: theme),
                _PhoneShowcaseSection(
                  key: const ValueKey('phone-showcase-section'),
                  theme: theme,
                  services: [
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
                  ],
                ),
              ],
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
        color: AppColors.emergency,
        icon: const Icon(Icons.emergency_outlined),
      );
    }
    return Tooltip(
      message: hint,
      child: TextButton.icon(
        key: const ValueKey('public-header-sos'),
        onPressed: go,
        style: TextButton.styleFrom(foregroundColor: AppColors.emergency),
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      elevation: 0,
      scrolledUnderElevation: 2,
      pinned: true,
      centerTitle: false,
      automaticallyImplyLeading: false,
      toolbarHeight: isDesktop ? 72 : 60,
      leadingWidth: isDesktop ? null : 56,
      leading: isDesktop ? null : const _HeaderSosButton(compact: true),
      titleSpacing: AppSpacing.lg,
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
      color: Theme.of(context).colorScheme.onSurface,
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
      child: Text(
        swahili ? 'EN' : 'SW',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

// ====================================================================== hero

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.isDesktop, required this.theme});

  final bool isDesktop;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final content = Column(
      crossAxisAlignment: isDesktop
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          s.tr('home.heroTitle'),
          textAlign: isDesktop ? TextAlign.start : TextAlign.center,
          style: theme.textTheme.displaySmall?.copyWith(
            color: Colors.white,
            fontSize: isDesktop ? 52 : 38,
            fontWeight: FontWeight.w800,
            height: 1.05,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          s.tr('home.heroSubtitle'),
          textAlign: isDesktop ? TextAlign.start : TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: AppColors.lightRed,
            fontWeight: FontWeight.w600,
            height: 1.25,
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
              onPressed: () => Navigator.pushNamed(context, '/signup'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.emergency,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
              ),
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: Text(s.tr('home.heroPrimaryCta')),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pushNamed(context, '/login'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
              ),
              child: Text(s.tr('common.signIn')),
            ),
          ],
        ),
      ],
    );

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, AppColors.navyDeep, AppColors.blue],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -80,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: .22),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -140,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                color: AppColors.emergency.withValues(alpha: .10),
                shape: BoxShape.circle,
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: isDesktop ? AppSpacing.huge : AppSpacing.xxl,
                horizontal: isDesktop ? AppSpacing.xxxl : AppSpacing.lg,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (isDesktop) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(flex: 6, child: content),
                        const SizedBox(width: AppSpacing.xxxl),
                        const Expanded(flex: 4, child: _HeroBrandPanel()),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      content,
                      const SizedBox(height: AppSpacing.xl),
                      const _HeroBrandPanel(),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBrandPanel extends StatelessWidget {
  const _HeroBrandPanel();

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .07),
        borderRadius: AppShapes.hero,
        border: Border.all(color: Colors.white.withValues(alpha: .15)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: .24),
            offset: const Offset(0, 24),
            blurRadius: 48,
            spreadRadius: -16,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppLogo(height: 128),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppStrings.appName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            s.tr('home.tagline'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.lg),
          Divider(color: Colors.white.withValues(alpha: .16), height: 1),
          const SizedBox(height: AppSpacing.lg),
          for (final (index, item) in <({String label, IconData icon})>[
            (label: s.tr('home.heroPanelOne'), icon: Icons.favorite_outline),
            (label: s.tr('home.heroPanelTwo'), icon: Icons.lock_outline),
            (label: s.tr('home.heroPanelThree'), icon: Icons.groups_outlined),
          ].indexed) ...[
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
                  child: Icon(item.icon, size: 17, color: Colors.white),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    item.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (index < 2) const SizedBox(height: AppSpacing.sm),
          ],
        ],
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

/// The signed-in app mockup, kept as the final public-home surface.
///
/// The former "Complete Care, One Platform" badge, heading, copy, service
/// checklist and card chrome are intentionally gone; only the unchanged phone
/// mockup remains.
class _PhoneShowcaseSection extends StatelessWidget {
  const _PhoneShowcaseSection({
    super.key,
    required this.theme,
    required this.services,
  });

  final ThemeData theme;
  final List<_ServiceSpec> services;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width > 1024;
    return Container(
      color: scheme.surface,
      padding: EdgeInsets.fromLTRB(
        wide ? AppSpacing.xxxl : AppSpacing.xxl,
        wide ? AppSpacing.xxxl : AppSpacing.xl,
        wide ? AppSpacing.xxxl : AppSpacing.xxl,
        wide ? AppSpacing.lg : AppSpacing.md,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: _PhoneShowcase(theme: theme, services: services),
        ),
      ),
    );
  }
}

/// Phone mockup of the signed-in app: status notch, brand app bar, a compact
/// greeting, a 7-tile quick-action grid (every tile routes to its real
/// destination) and a red SOS strip — ringed by six floating healthcare icons
/// that reveal with a short staggered rise. The reveal is finite, so widget
/// tests that settle the page still finish.
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

