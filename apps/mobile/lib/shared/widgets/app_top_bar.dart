import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'app_avatar.dart';

/// Sickler's Warriors — TopBar system (FRONTEND-1).
///
/// Standard navy top bar for every major patient screen. It can carry a back
/// button, title, contextual actions (typically a notification button + avatar)
/// but stays uncluttered. The Home screen may prefer a personalised header
/// instead of a title-only bar ([AppHomeHeader]).
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    this.title,
    this.leading,
    this.showBack = false,
    this.actions = const [],
    this.onNotificationsTap,
    this.onAvatarTap,
    this.avatarName,
    this.avatarImageUrl,
    this.unreadCount = 0,
    this.bottom,
  });

  final String? title;
  final Widget? leading;
  final bool showBack;
  final List<Widget> actions;
  final VoidCallback? onNotificationsTap;
  final VoidCallback? onAvatarTap;
  final String? avatarName;
  final String? avatarImageUrl;
  final int unreadCount;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(64 + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.navy,
      leading: leading ??
          (showBack
              ? IconButton(
                  tooltip: tr('common.back'),
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.maybePop(context),
                )
              : null),
      title: title == null ? null : Text(title!),
      actions: [
        if (onNotificationsTap != null)
          IconButton(
            tooltip: tr('common.notifications'),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_outlined),
                if (unreadCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.emergency,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        style: const TextStyle(
                          color: AppColors.textOnEmergency,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: onNotificationsTap,
          ),
        if (onAvatarTap != null) ...[
          const SizedBox(width: AppSpacing.xs),
          AppAvatar(
            name: avatarName,
            imageUrl: avatarImageUrl,
            radius: 17,
            backgroundColor: AppColors.blue,
            onTap: onAvatarTap,
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        ...actions,
      ],
      bottom: bottom,
    );
  }
}

/// Notification label referenced without pulling feature constants in core.
abstract final class AppStringsNotif {
  static const String notifications = 'Notifications'; // keep for backward compat if used elsewhere; prefer tr() in UI
}

/// Home screen personalised header — greeting + avatar + notification entry.
///
/// This is the "personalized header" style allowed for Home instead of a
/// plain title bar. FRONTEND-2 builds the full dashboard underneath it.
class AppHomeHeader extends StatelessWidget {
  const AppHomeHeader({
    super.key,
    this.greeting = 'Habari',
    this.personName,
    this.subtitle,
    this.onNotificationsTap,
    this.onAvatarTap,
    this.avatarName,
    this.avatarImageUrl,
    this.unreadCount = 0,
  });

  final String? greeting;
  final String? personName;
  final String? subtitle;
  final VoidCallback? onNotificationsTap;
  final VoidCallback? onAvatarTap;
  final String? avatarName;
  final String? avatarImageUrl;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(color: AppColors.navy),
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: AppSpacing.lg,
        top: MediaQuery.paddingOf(context).top + AppSpacing.md,
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          Text(
            personName == null
                ? (greeting ?? tr('common.greeting'))
                : '${greeting ?? tr('common.greeting')}, $personName',
            style: AppTypography.headline.copyWith(
              color: AppColors.textOnDark,
              fontSize: 22,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textOnDark.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onNotificationsTap != null)
              IconButton(
                tooltip: tr('common.notifications'),
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(
                      Icons.notifications_outlined,
                      color: AppColors.textOnDark,
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          decoration: const BoxDecoration(
                            color: AppColors.emergency,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            unreadCount > 9 ? '9+' : '$unreadCount',
                            style: const TextStyle(
                              color: AppColors.textOnEmergency,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                onPressed: onNotificationsTap,
              ),
            if (onAvatarTap != null) ...[
              const SizedBox(width: AppSpacing.xs),
              AppAvatar(
                name: avatarName,
                imageUrl: avatarImageUrl,
                radius: 19,
                backgroundColor: AppColors.blue,
                onTap: onAvatarTap,
              ),
            ],
          ],
        ),
      ),
    );
  }
}