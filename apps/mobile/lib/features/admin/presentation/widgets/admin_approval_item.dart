import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_badges.dart';

/// Approval item widget for pending approvals list (FRONTEND-4).
///
/// Displays a single item awaiting administrative review with type,
/// submitted date, status, and action buttons.
class AdminApprovalItem extends StatelessWidget {
  const AdminApprovalItem({
    super.key,
    required this.item,
    required this.onView,
    required this.onApprove,
    required this.onReject,
  });

  final ApprovalItem item;
  final VoidCallback onView;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          AppBadge(
                            label: item.type,
                            tone: _badgeToneForType(item.type),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            '${tr('admin.submittedAt')} ${item.submittedDate}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                AppBadge(
                  label: item.status,
                  tone: _badgeToneForStatus(item.status),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onView,
                  child: Text(tr('admin.view')),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.emergency,
                    side: BorderSide(color: AppColors.emergency.withValues(alpha: 0.5)),
                  ),
                  child: Text(tr('admin.reject')),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: onApprove,
                  child: Text(tr('admin.approve')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  BadgeTone _badgeToneForType(String type) {
    switch (type.toLowerCase()) {
      case 'doctor':
      case 'organization':
        return BadgeTone.info;
      case 'campaign':
      case 'education':
        return BadgeTone.neutral;
      default:
        return BadgeTone.neutral;
    }
  }

  BadgeTone _badgeToneForStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return BadgeTone.warning;
      case 'approved':
        return BadgeTone.success;
      case 'rejected':
        return BadgeTone.emergency;
      default:
        return BadgeTone.neutral;
    }
  }
}

class ApprovalItem {
  const ApprovalItem({
    required this.id,
    required this.title,
    required this.type,
    required this.submittedDate,
    required this.status,
  });

  final String id;
  final String title;
  final String type;
  final String submittedDate;
  final String status;
}
