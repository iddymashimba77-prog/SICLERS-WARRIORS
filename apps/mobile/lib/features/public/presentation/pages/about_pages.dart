import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../core/theme/app_spacing.dart';

/// Supplied Sickler's Warriors contact numbers, kept as single-source
/// constants so the public site, copy and tests can never drift apart.
class ContactNumbers {
  const ContactNumbers._();

  /// Primary contact number, displayed exactly as provided.
  static const String primaryDisplay = '+255 763 801 187';

  /// [primaryDisplay] in Tanzanian local format.
  static const String primaryLocal = '0763801187';

  /// [primaryDisplay] as a dialable `tel:` path (E.164).
  static const String primaryTel = '+255763801187';

  /// Secondary contact number, displayed exactly as provided.
  static const String secondaryDisplay = '+255 683 328 789';

  /// [secondaryDisplay] in Tanzanian local format.
  static const String secondaryLocal = '0683328789';

  /// [secondaryDisplay] as a dialable `tel:` path (E.164).
  static const String secondaryTel = '+255683328789';

  /// The `tel:` URI used for dialling [e164].
  static Uri telUri(String e164) => Uri(scheme: 'tel', path: e164);
}

/// Shared scaffold for the five public "About" surfaces reached from the
/// public home menu: section app bar, branded hero (icon, optional campaign
/// headline, section subtitle) and a scrollable, width-constrained body.
class AboutPageShell extends StatelessWidget {
  const AboutPageShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.heroIcon,
    this.headline,
    this.children = const <Widget>[],
  });

  final String title;
  final String subtitle;
  final IconData heroIcon;

  /// Optional large brand headline shown inside the hero.
  final String? headline;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenEdge,
            AppSpacing.lg,
            AppSpacing.screenEdge,
            AppSpacing.huge,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSpacing.contentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AboutHero(
                    icon: heroIcon,
                    headline: headline,
                    subtitle: subtitle,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// About Sickler's Warriors — the public landing page of the About menu.
class AboutWarriorsPage extends StatelessWidget {
  const AboutWarriorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AboutPageShell(
      title: s.tr('about.about'),
      subtitle: s.tr('about.aboutBody'),
      headline: s.tr('about.headline'),
      heroIcon: Icons.diversity_3,
      children: [
        _Lead(s.tr('about.intro1')),
        const SizedBox(height: AppSpacing.lg),
        _Lead(s.tr('about.intro2')),
        const SizedBox(height: AppSpacing.lg),
        _Lead(s.tr('about.intro3')),
        const SizedBox(height: AppSpacing.xl),
        _SectionHeading(s.tr('about.whoTitle')),
        const SizedBox(height: AppSpacing.md),
        _BulletCard(
          icon: Icons.stars_outlined,
          text: s.tr('about.serveWarriors'),
        ),
        const SizedBox(height: AppSpacing.md),
        _BulletCard(
          icon: Icons.family_restroom_outlined,
          text: s.tr('about.serveFamilies'),
        ),
        const SizedBox(height: AppSpacing.md),
        _BulletCard(
          icon: Icons.medical_services_outlined,
          text: s.tr('about.serveProfessionals'),
        ),
        const SizedBox(height: AppSpacing.md),
        _BulletCard(
          icon: Icons.volunteer_activism_outlined,
          text: s.tr('about.serveProviders'),
        ),
        const SizedBox(height: AppSpacing.xl),
        _SectionHeading(s.tr('about.accessTitle')),
        const SizedBox(height: AppSpacing.md),
        _BulletCard(
          icon: Icons.menu_book_outlined,
          text: s.tr('about.accessEducation'),
        ),
        const SizedBox(height: AppSpacing.md),
        _BulletCard(
          icon: Icons.handshake_outlined,
          text: s.tr('about.accessConnect'),
        ),
        const SizedBox(height: AppSpacing.md),
        _BulletCard(
          icon: Icons.monitor_heart_outlined,
          text: s.tr('about.accessTracking'),
        ),
        const SizedBox(height: AppSpacing.md),
        _BulletCard(
          icon: Icons.event_available_outlined,
          text: s.tr('about.accessAppointments'),
        ),
        const SizedBox(height: AppSpacing.md),
        _BulletCard(
          icon: Icons.psychology_outlined,
          text: s.tr('about.accessSupport'),
        ),
        const SizedBox(height: AppSpacing.md),
        _BulletCard(
          icon: Icons.bloodtype_outlined,
          text: s.tr('about.accessBlood'),
          accent: AppColors.emergency,
        ),
        const SizedBox(height: AppSpacing.md),
        _BulletCard(
          icon: Icons.forum_outlined,
          text: s.tr('about.accessCommunity'),
        ),
        const SizedBox(height: AppSpacing.lg),
        _NoteCard(icon: Icons.info_outline, text: s.tr('about.availabilityNote')),
        const SizedBox(height: AppSpacing.xl),
        _JoinCtaRow(joinLabel: s.tr('about.ctaJoin')),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton(
          onPressed: () => Navigator.pushNamed(context, '/news'),
          child: Text(s.tr('about.ctaExplore')),
        ),
      ],
    );
  }
}

/// Our Mission — mission statement, vision statement and the six core values.
class MissionPage extends StatelessWidget {
  const MissionPage({super.key});

  static const List<_Value> _values = <_Value>[
    _Value('about.valueCompassionT', 'about.valueCompassionB', Icons.favorite_border),
    _Value('about.valueAccessT', 'about.valueAccessB', Icons.travel_explore),
    _Value('about.valueCommunityT', 'about.valueCommunityB', Icons.diversity_3),
    _Value('about.valueTrustT', 'about.valueTrustB', Icons.shield_outlined),
    _Value('about.valueEmpowermentT', 'about.valueEmpowermentB', Icons.verified_user_outlined),
    _Value('about.valueInnovationT', 'about.valueInnovationB', Icons.lightbulb_outline),
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AboutPageShell(
      title: s.tr('about.mission'),
      subtitle: s.tr('about.missionBody'),
      heroIcon: Icons.track_changes,
      children: [
        _StatementCard(
          icon: Icons.flag_outlined,
          title: s.tr('about.missionCardTitle'),
          body: s.tr('about.missionStatement'),
        ),
        const SizedBox(height: AppSpacing.lg),
        _StatementCard(
          icon: Icons.visibility_outlined,
          title: s.tr('about.visionTitle'),
          body: s.tr('about.visionStatement'),
        ),
        const SizedBox(height: AppSpacing.xl),
        _SectionHeading(s.tr('about.valuesTitle')),
        const SizedBox(height: AppSpacing.md),
        _ValueGrid(
          values: _values
              .map((v) => _ResolvedValue(
                    title: s.tr(v.titleKey),
                    body: s.tr(v.bodyKey),
                    icon: v.icon,
                  ))
              .toList(growable: false),
        ),
      ],
    );
  }
}

/// How It Works — the six numbered steps from sign-up to community support.
class HowItWorksPage extends StatelessWidget {
  const HowItWorksPage({super.key});

  static const List<_Step> _steps = <_Step>[
    _Step(Icons.person_add_alt_1_outlined),
    _Step(Icons.account_circle_outlined),
    _Step(Icons.menu_book_outlined),
    _Step(Icons.handshake_outlined),
    _Step(Icons.monitor_heart_outlined),
    _Step(Icons.healing_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AboutPageShell(
      title: s.tr('about.howItWorks'),
      subtitle: s.tr('about.howItWorksBody'),
      heroIcon: Icons.route_outlined,
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          _StepCard(
            number: i + 1,
            icon: _steps[i].icon,
            title: s.tr('about.step${i + 1}T'),
            body: s.tr('about.step${i + 1}B'),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        _NoteCard(icon: Icons.info_outline, text: s.tr('about.howNote')),
        const SizedBox(height: AppSpacing.xl),
        _JoinCtaRow(joinLabel: s.tr('about.ctaJoin')),
      ],
    );
  }
}

/// Team & Partners — the project team and the intended collaboration areas.
class TeamPage extends StatelessWidget {
  const TeamPage({super.key});

  static const List<_TeamMember> _members = <_TeamMember>[
    _TeamMember('Iddy Mashimba', 'IM', 'about.teamIddyBody'),
    _TeamMember('Michael Yohana', 'MY', 'about.teamMichaelBody'),
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AboutPageShell(
      title: s.tr('about.team'),
      subtitle: s.tr('about.teamBody'),
      heroIcon: Icons.group_outlined,
      children: [
        _Lead(s.tr('about.teamIntro')),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 680;
            final gap = AppSpacing.lg;
            final width = twoColumns
                ? (constraints.maxWidth - gap) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final member in _members)
                  SizedBox(
                    width: width,
                    child: _TeamMemberCard(
                      member: member,
                      role: s.tr('about.teamRole'),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        _SectionHeading(s.tr('about.collabTitle')),
        const SizedBox(height: AppSpacing.sm),
        _Lead(s.tr('about.collabBody')),
        const SizedBox(height: AppSpacing.md),
        _BulletCard(
          icon: Icons.medical_services_outlined,
          text: s.tr('about.collab1'),
        ),
        const SizedBox(height: AppSpacing.md),
        _BulletCard(
          icon: Icons.forum_outlined,
          text: s.tr('about.collab2'),
        ),
        const SizedBox(height: AppSpacing.md),
        _BulletCard(
          icon: Icons.family_restroom_outlined,
          text: s.tr('about.collab3'),
        ),
        const SizedBox(height: AppSpacing.md),
        _BulletCard(
          icon: Icons.apartment_outlined,
          text: s.tr('about.collab4'),
        ),
      ],
    );
  }
}

/// Contact Us — direct dial cards for the supplied contact numbers.
class ContactUsPage extends StatelessWidget {
  const ContactUsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AboutPageShell(
      title: s.tr('about.contact'),
      subtitle: s.tr('about.contactBody'),
      headline: s.tr('about.contactHeadline'),
      heroIcon: Icons.call_outlined,
      children: [
        _Lead(s.tr('about.contactIntro')),
        const SizedBox(height: AppSpacing.lg),
        _ContactCard(
          callLabel: s.tr('about.contactCallUs'),
          display: ContactNumbers.primaryDisplay,
          local: ContactNumbers.primaryLocal,
          e164: ContactNumbers.primaryTel,
        ),
        const SizedBox(height: AppSpacing.md),
        _ContactCard(
          callLabel: s.tr('about.contactCallUs'),
          display: ContactNumbers.secondaryDisplay,
          local: ContactNumbers.secondaryLocal,
          e164: ContactNumbers.secondaryTel,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// shared building blocks
// ---------------------------------------------------------------------------

class _AboutHero extends StatelessWidget {
  const _AboutHero({
    required this.icon,
    required this.headline,
    required this.subtitle,
  });

  final IconData icon;
  final String? headline;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: dark ? AppColors.blue.withValues(alpha: .30) : AppColors.lightBlue,
        borderRadius: AppShapes.card,
        border: Border.all(color: AppColors.blue.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconChip(icon: icon, size: 48),
          if (headline != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              headline!,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: dark ? AppColors.textOnDark : AppColors.darkRed,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Text(
            subtitle,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: dark
                  ? AppColors.textOnDark.withValues(alpha: .85)
                  : theme.colorScheme.onSurfaceVariant,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({
    required this.icon,
    this.accent = AppColors.blue,
    this.size = 40,
  });

  final IconData icon;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .12),
        borderRadius: AppShapes.small,
      ),
      child: Icon(icon, color: accent, size: size * .55),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleLarge?.copyWith(
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _Lead extends StatelessWidget {
  const _Lead(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.55,
      ),
    );
  }
}

class _BulletCard extends StatelessWidget {
  const _BulletCard({
    required this.icon,
    required this.text,
    this.accent = AppColors.blue,
  });

  final IconData icon;
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppShapes.tile,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _IconChip(icon: icon, accent: accent, size: 36),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.lightAmber,
        borderRadius: AppShapes.tile,
        border: Border.all(color: AppColors.warning.withValues(alpha: .45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.warning, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatementCard extends StatelessWidget {
  const _StatementCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppShapes.card,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconChip(icon: icon, size: 36),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            body,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _JoinCtaRow extends StatelessWidget {
  const _JoinCtaRow({required this.joinLabel});

  final String joinLabel;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton(
          onPressed: () => Navigator.pushNamed(context, '/signup'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.emergency,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.md,
            ),
          ),
          child: Text(joinLabel),
        ),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
  });

  final int number;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppShapes.tile,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.blue,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.textOnBlue,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IconChip(icon: icon, size: 32),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xxs),
                        child: Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamMemberCard extends StatelessWidget {
  const _TeamMemberCard({required this.member, required this.role});

  final _TeamMember member;
  final String role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppShapes.card,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: AppColors.lightBlue,
                child: Text(
                  member.initials,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.blue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.lightBlue,
                        borderRadius: AppShapes.pill,
                        border: Border.all(
                          color: AppColors.blue.withValues(alpha: .35),
                        ),
                      ),
                      child: Text(
                        role,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            s.tr(member.bodyKey),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.callLabel,
    required this.display,
    required this.local,
    required this.e164,
  });

  final String callLabel;
  final String display;
  final String local;
  final String e164;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: '$callLabel $display',
      child: InkWell(
        borderRadius: AppShapes.tile,
        onTap: () => _dial(context, s, e164),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: AppShapes.tile,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const _IconChip(icon: Icons.call_outlined, size: 40),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      callLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      display,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      local,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.call_outlined,
                color: AppColors.blue,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ValueGrid extends StatelessWidget {
  const _ValueGrid({required this.values});

  final List<_ResolvedValue> values;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 960
            ? 3
            : constraints.maxWidth >= 620
                ? 2
                : 1;
        const gap = AppSpacing.md;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final value in values)
              SizedBox(
                width: width,
                child: _ValueCard(value: value),
              ),
          ],
        );
      },
    );
  }
}

class _ValueCard extends StatelessWidget {
  const _ValueCard({required this.value});

  final _ResolvedValue value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppShapes.tile,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconChip(icon: value.icon, size: 32),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  value.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value.body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _dial(
  BuildContext context,
  AppLocalizations s,
  String e164,
) async {
  try {
    final opened = await launchUrl(
      ContactNumbers.telUri(e164),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      _showDialError(context, s, e164);
    }
  } catch (_) {
    if (context.mounted) {
      _showDialError(context, s, e164);
    }
  }
}

void _showDialError(BuildContext context, AppLocalizations s, String e164) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(s.tr('sos.cannotDial', args: {'service': e164})),
    ),
  );
}

class _Value {
  const _Value(this.titleKey, this.bodyKey, this.icon);

  final String titleKey;
  final String bodyKey;
  final IconData icon;
}

class _ResolvedValue {
  const _ResolvedValue({required this.title, required this.body, required this.icon});

  final String title;
  final String body;
  final IconData icon;
}

class _Step {
  const _Step(this.icon);

  final IconData icon;
}

class _TeamMember {
  const _TeamMember(this.name, this.initials, this.bodyKey);

  final String name;
  final String initials;
  final String bodyKey;
}
