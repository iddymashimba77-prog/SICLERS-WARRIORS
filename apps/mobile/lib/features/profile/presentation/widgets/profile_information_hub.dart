import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../public/presentation/pages/about_pages.dart';

/// Information hub pinned to the bottom of the authenticated Profile.
///
/// Centralises the organization's informational pages (About, Mission, How It
/// Works, Team and Contact) that previously lived on the public landing page.
/// Every row opens the same existing page, so no content or destination is
/// lost while the Home surface stays focused on care.
class ProfileInformationHub extends StatelessWidget {
  const ProfileInformationHub({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      key: const Key('profile-info-hub'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.blue.withValues(alpha: .16),
                    AppColors.navy.withValues(alpha: .08),
                  ],
                ),
                borderRadius: AppShapes.tile,
                border: Border.all(
                  color: AppColors.blue.withValues(alpha: .18),
                ),
              ),
              child: const Icon(
                Icons.info_outline,
                size: 22,
                color: AppColors.blue,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.tr('profile.infoHubTitle'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    s.tr('profile.infoHubSubtitle'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _InfoGroup(
          title: s.tr('profile.infoGroupAbout'),
          items: [
            _InfoItem(
              icon: Icons.volunteer_activism_outlined,
              title: s.tr('about.about'),
              subtitle: s.tr('profile.infoAboutSubtitle'),
              page: const AboutWarriorsPage(),
            ),
            _InfoItem(
              icon: Icons.track_changes_outlined,
              title: s.tr('about.mission'),
              subtitle: s.tr('profile.infoMissionSubtitle'),
              page: const MissionPage(),
            ),
            _InfoItem(
              icon: Icons.account_tree_outlined,
              title: s.tr('about.howItWorks'),
              subtitle: s.tr('profile.infoHowSubtitle'),
              page: const HowItWorksPage(),
            ),
            _InfoItem(
              icon: Icons.groups_outlined,
              title: s.tr('about.team'),
              subtitle: s.tr('profile.infoTeamSubtitle'),
              page: const TeamPage(),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _InfoGroup(
          title: s.tr('profile.infoGroupSupport'),
          items: [
            _InfoItem(
              icon: Icons.mail_outline,
              title: s.tr('about.contact'),
              subtitle: s.tr('profile.infoContactSubtitle'),
              page: const ContactUsPage(),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoGroup extends StatelessWidget {
  const _InfoGroup({required this.title, required this.items});

  final String title;
  final List<_InfoItem> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppShapes.card,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 64,
                endIndent: AppSpacing.lg,
                color: scheme.outlineVariant.withValues(alpha: .6),
              ),
            _InfoRow(item: items[i]),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.item});

  final _InfoItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const accent = AppColors.blue;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .12),
          borderRadius: AppShapes.tile,
        ),
        child: Icon(item.icon, size: 20, color: accent),
      ),
      title: Text(
        item.title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      subtitle: Text(
        item.subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
          height: 1.35,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        size: 20,
        color: scheme.onSurfaceVariant,
      ),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => item.page)),
    );
  }
}

class _InfoItem {
  const _InfoItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.page,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget page;
}
