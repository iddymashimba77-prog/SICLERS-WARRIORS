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
import 'about_pages.dart';
import '../../../../core/theme/app_shapes.dart';

/// Public landing page for Sickler's Warriors (FINALIZE public home).
///
/// A public brand experience built around a calm, premium care journey:
/// pinned header with mega-menus, an editorial hero, and the seven service
/// pillars with the signed-in app showcase. News and
/// announcements are deliberately absent from the public surface.
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
                _WarriorNeedsSection(
                  key: const ValueKey('warrior-needs-section'),
                  theme: theme,
                  services: [
                    _ServiceSpec(
                      title: s.tr('srv.healthTitle'),
                      subtitle: s.tr('srv.healthSubtitle'),
                      icon: Icons.health_and_safety_outlined,
                      actions: const [
                        _SectionAction(labelKey: 'act.healthDashboard', route: '/health'),
                        _SectionAction(labelKey: 'act.manageMedication', route: '/medication'),
                      ],
                    ),
                    _ServiceSpec(
                      title: s.tr('srv.doctorTitle'),
                      subtitle: s.tr('srv.doctorSubtitle'),
                      icon: Icons.medical_services_outlined,
                      actions: const [
                        _SectionAction(labelKey: 'act.findDoctor', route: '/doctors'),
                        _SectionAction(labelKey: 'act.visitClinic', route: '/clinic'),
                      ],
                    ),
                    _ServiceSpec(
                      title: s.tr('srv.bloodTitle'),
                      subtitle: s.tr('srv.bloodSubtitle'),
                      icon: Icons.bloodtype_outlined,
                      emergency: true,
                      actions: const [
                        _SectionAction(labelKey: 'act.bloodNetwork', route: '/blood-donation'),
                        _SectionAction(labelKey: 'act.donateBlood', route: '/donor-home'),
                      ],
                    ),
                    _ServiceSpec(
                      title: s.tr('srv.emergencyTitle'),
                      subtitle: s.tr('srv.emergencySubtitle'),
                      icon: Icons.emergency_outlined,
                      emergency: true,
                      actions: const [
                        _SectionAction(labelKey: 'act.emergencySos', route: '/emergency'),
                      ],
                    ),
                    _ServiceSpec(
                      title: s.tr('srv.educationTitle'),
                      subtitle: s.tr('srv.educationSubtitle'),
                      icon: Icons.school_outlined,
                      actions: const [
                        _SectionAction(labelKey: 'act.openAcademy', route: '/education'),
                      ],
                    ),
                    _ServiceSpec(
                      title: s.tr('srv.communityTitle'),
                      subtitle: s.tr('srv.communitySubtitle'),
                      icon: Icons.forum_outlined,
                      actions: const [
                        _SectionAction(labelKey: 'act.joinCommunity', route: '/community'),
                        _SectionAction(labelKey: 'act.messages', route: '/messages'),
                        _SectionAction(labelKey: 'act.aiCoach', route: '/ai-assistant'),
                      ],
                    ),
                    _ServiceSpec(
                      title: s.tr('srv.donateTitle'),
                      subtitle: s.tr('srv.donateSubtitle'),
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

  void _go(BuildContext context, _MenuLink link) {
    if (link.route.isNotEmpty) {
      goTo(context, link.route);
    } else if (link.page != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => link.page!),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final menus = _megaMenusFor(s);
    final compactHeader = !isDesktop &&
        MediaQuery.sizeOf(context).width < 720;
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
      titleSpacing: isDesktop ? AppSpacing.lg : 0,
      title: isDesktop
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, entry) in menus.entries.indexed) ...[
                  if (index > 0) const SizedBox(width: AppSpacing.xs),
                  _HeaderMenuButton(
                    label: entry.key,
                    links: entry.value,
                    onSelected: (l) => _go(context, l),
                  ),
                ],
              ],
            )
          : null,
      actions: isDesktop
          ? [
              const _HeaderSosButton(),
              const SizedBox(width: AppSpacing.sm),
              const _PublicThemeToggle(),
              const _PublicLanguageToggle(),
              const SizedBox(width: AppSpacing.xs),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/login'),
                child: Text(s.tr('common.signIn')),
              ),
              const SizedBox(width: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: FilledButton(
                  onPressed: () => Navigator.pushNamed(context, '/signup'),
                  child: Text(s.tr('common.signUp')),
                ),
              ),
            ]
          : compactHeader
              ? [
                  const _PublicThemeToggle(),
                  const _PublicLanguageToggle(),
                  IconButton(
                    tooltip: s.tr('home.explore'),
                    onPressed: () => _showMobileMenu(context),
                    icon: const Icon(Icons.menu),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ]
              : [
                  const _PublicThemeToggle(),
                  const _PublicLanguageToggle(),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/login'),
                    child: Text(s.tr('common.signIn')),
                  ),
                  IconButton(
                    tooltip: s.tr('home.explore'),
                    onPressed: () => _showMobileMenu(context),
                    icon: const Icon(Icons.menu),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
    );
  }

  void _showMobileMenu(BuildContext context) {
    final s = AppLocalizations.of(context);
    final entries = _megaMenusFor(s).entries.toList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.emergency_outlined,
                    color: AppColors.emergency,
                  ),
                  title: Text(
                    s.tr('home.sosHint'),
                    style: const TextStyle(
                      color: AppColors.emergency,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    goTo(context, '/emergency');
                  },
                ),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                for (final entry in entries) ...[
                  _MobileMenuCategory(
                    title: entry.key,
                    links: entry.value,
                    onSelected: (link) {
                      Navigator.of(sheetContext).pop();
                      _go(context, link);
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                ListTile(
                  leading: const Icon(Icons.login),
                  title: Text(s.tr('common.signIn')),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.pushNamed(context, '/login');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1),
                  title: Text(s.tr('common.createAccount')),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.pushNamed(context, '/signup');
                  },
                ),
              ],
            ),
          ),
        );
      },
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

class _HeaderMenuButton extends StatelessWidget {
  const _HeaderMenuButton({
    required this.label,
    required this.links,
    required this.onSelected,
  });

  final String label;
  final List<_MenuLink> links;
  final ValueChanged<_MenuLink> onSelected;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final menuLabelStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        );
    return PopupMenuButton<_MenuLink>(
      key: Key('mega-$label'),
      tooltip: '$label ${s.tr('common.menuSuffix')}',
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final link in links)
          PopupMenuItem<_MenuLink>(
            value: link,
            height: 44,
            child: Row(
              children: [
                Icon(
                  link.icon,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(link.label),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(label, style: menuLabelStyle),
      ),
    );
  }
}

class _MobileMenuCategory extends StatelessWidget {
  const _MobileMenuCategory({
    required this.title,
    required this.links,
    required this.onSelected,
  });

  final String title;
  final List<_MenuLink> links;
  final ValueChanged<_MenuLink> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: .8,
            color: theme.colorScheme.primary,
          ),
        ),
        for (final link in links)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
              link.icon,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(link.label),
            onTap: () => onSelected(link),
          ),
      ],
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

/// One public service area: localized copy, icon, priority action routes.
///
/// Drives both the compact checklist inside the section's hero card and the
/// full action cards rendered beneath it.
class _ServiceSpec {
  const _ServiceSpec({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actions,
    this.emergency = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<_SectionAction> actions;
  final bool emergency;
}

/// "Everything a Warrior Needs" — the premium mid-page service showcase.
///
/// A light-blue → white band holds one bevelled, shadowed container: on the
/// left the badge, heading, copy, a compact tappable checklist of all seven
/// services and the "Explore All Services" CTA; on the right a phone mockup of
/// the signed-in app surrounded by floating healthcare icons. The CTA scrolls
/// to the full service cards (with their real route actions) that render
/// directly beneath the container inside the same band.
class _WarriorNeedsSection extends StatefulWidget {
  const _WarriorNeedsSection({
    super.key,
    required this.theme,
    required this.services,
  });

  final ThemeData theme;
  final List<_ServiceSpec> services;

  @override
  State<_WarriorNeedsSection> createState() => _WarriorNeedsSectionState();
}

class _WarriorNeedsSectionState extends State<_WarriorNeedsSection> {
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = widget.theme;
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final wide = MediaQuery.of(context).size.width > 1024;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [scheme.surfaceContainerLow, scheme.surfaceContainer]
              : [scheme.primaryContainer.withValues(alpha: 0.28), AppColors.surface],
        ),
      ),
      padding: EdgeInsets.symmetric(
        vertical: AppSpacing.xxxl,
        horizontal: wide ? AppSpacing.xxxl : AppSpacing.lg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSpacing.contentMaxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _heroCard(context, s, dark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroCard(BuildContext context, AppLocalizations s, bool dark) {
    final scheme = widget.theme.colorScheme;
    final pad = MediaQuery.of(context).size.width > 1024
        ? AppSpacing.xxl
        : AppSpacing.lg;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [scheme.surfaceContainerHigh, scheme.surfaceContainer]
              : [AppColors.surface, scheme.primaryContainer.withValues(alpha: 0.24)],
        ),
        borderRadius: AppShapes.hero,
        border: Border.all(
          color: dark ? AppColors.dividerOnDark : AppColors.borderSubtle,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: dark ? .35 : .10),
            offset: const Offset(0, 18),
            blurRadius: 44,
            spreadRadius: -14,
          ),
          BoxShadow(
            color: AppColors.navy.withValues(alpha: dark ? .20 : .06),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      padding: EdgeInsets.all(pad),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoCol = constraints.maxWidth >= 640;
          final copy = _heroCopy(context, s, dark);
          final showcase = Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: _PhoneShowcase(
              theme: widget.theme,
              services: widget.services,
            ),
          );
          if (!twoCol) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                copy,
                const SizedBox(height: AppSpacing.xl),
                showcase,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 11, child: copy),
              const SizedBox(width: AppSpacing.xl),
              Expanded(flex: 9, child: showcase),
            ],
          );
        },
      ),
    );
  }

  Widget _heroCopy(BuildContext context, AppLocalizations s, bool dark) {
    final theme = widget.theme;
    final scheme = theme.colorScheme;
    final headingSize =
        MediaQuery.of(context).size.width > 1024 ? 36.0 : 30.0;
    final badgeBg =
        dark ? AppColors.blue.withValues(alpha: .30) : AppColors.lightBlue;
    final badgeFg = dark ? AppColors.textOnDark : AppColors.blue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: badgeBg,
            borderRadius: AppShapes.pill,
            border: Border.all(color: AppColors.blue.withValues(alpha: .3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_outlined, size: 16, color: badgeFg),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  s.tr('home.servicesBadge'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: badgeFg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          s.tr('home.sectionsTitle'),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: headingSize,
            height: 1.15,
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          s.tr('home.sectionsSubtitle'),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.55,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final (index, spec) in widget.services.indexed) ...[
          _serviceRow(context, spec),
          if (index < widget.services.length - 1)
            const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  Widget _serviceRow(BuildContext context, _ServiceSpec spec) {
    final theme = widget.theme;
    final scheme = theme.colorScheme;
    final accent = spec.emergency ? AppColors.emergency : AppColors.blue;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppShapes.tile,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: AppShapes.tile,
        onTap: () => goTo(context, spec.actions.first.route),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: AppShapes.small,
                ),
                child: Icon(spec.icon, size: 18, color: accent),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      spec.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      spec.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
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

// ========================================================= mega menu model

class _MenuLink {
  const _MenuLink(this.label, {this.icon = Icons.arrow_forward_ios, this.route = '', this.page});

  final String label;
  final IconData icon;
  final String route;

  /// Page for destinations without a named route (About pages).
  final Widget? page;
}

Map<String, List<_MenuLink>> _megaMenusFor(AppLocalizations s) {
  return {
    s.tr('nav.about'): [
      _MenuLink(s.tr('about.about'), icon: Icons.volunteer_activism_outlined,
          page: const AboutWarriorsPage()),
      _MenuLink(s.tr('about.mission'), icon: Icons.track_changes_outlined,
          page: const MissionPage()),
      _MenuLink(s.tr('about.howItWorks'), icon: Icons.account_tree_outlined,
          page: const HowItWorksPage()),
      _MenuLink(s.tr('about.team'), icon: Icons.groups_outlined,
          page: const TeamPage()),
      _MenuLink(s.tr('about.contact'), icon: Icons.mail_outline,
          page: const ContactUsPage()),
    ],
    s.tr('nav.health'): [
      _MenuLink(s.tr('act.healthDashboard'), icon: Icons.monitor_heart_outlined, route: '/health'),
      _MenuLink(s.tr('act.manageMedication'), icon: Icons.medication_outlined, route: '/medication'),
      _MenuLink(s.tr('nav.records'), icon: Icons.folder_shared_outlined, route: '/records'),
      _MenuLink(s.tr('nav.timeline'), icon: Icons.timeline_outlined, route: '/health'),
      _MenuLink(s.tr('nav.appointments'), icon: Icons.event_available_outlined, route: '/clinic'),
    ],
    s.tr('nav.blood'): [
      _MenuLink(s.tr('act.bloodNetwork'), icon: Icons.bloodtype_outlined, route: '/blood-donation'),
      _MenuLink(s.tr('act.donateBlood'), icon: Icons.water_drop_outlined, route: '/donor-home'),
      _MenuLink(s.tr('nav.supportDonations'), icon: Icons.volunteer_activism_outlined, route: '/donations'),
    ],
    s.tr('nav.community'): [
      _MenuLink(s.tr('act.joinCommunity'), icon: Icons.forum_outlined, route: '/community'),
      _MenuLink(s.tr('act.messages'), icon: Icons.chat_bubble_outline, route: '/messages'),
      _MenuLink(s.tr('act.openAcademy'), icon: Icons.school_outlined, route: '/education'),
      _MenuLink(s.tr('act.aiCoach'), icon: Icons.smart_toy_outlined, route: '/ai-assistant'),
    ],
    s.tr('nav.resources'): [
      _MenuLink(s.tr('nav.education'), icon: Icons.menu_book_outlined, route: '/education'),
      _MenuLink(s.tr('act.emergencySos'), icon: Icons.emergency_outlined, route: '/emergency'),
      _MenuLink(s.tr('nav.records'), icon: Icons.event_note_outlined, route: '/records'),
      _MenuLink(s.tr('nav.supportDonations'), icon: Icons.volunteer_activism_outlined, route: '/donations'),
    ],
  };
}