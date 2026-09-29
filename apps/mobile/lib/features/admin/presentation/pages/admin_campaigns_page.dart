import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import '../widgets/admin_widgets.dart';

/// Campaign administration (ADMIN-3) — verification queue + active campaign
/// lifecycle (verify/pause/close) gated by campaigns.verify.
class AdminCampaignsPage extends StatelessWidget {
  const AdminCampaignsPage({super.key, this.repository, this.accessToken});

  static const String routeName = '/admin/campaigns';

  final AdminRepository? repository;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.controllerOf(context);
    final token = accessToken ?? session.accessToken;
    if (token == null) return const Center(child: Text('Not signed in.'));
    return _CampaignsView(
      accessToken: token,
      repository: repository ?? AdminRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class _CampaignsView extends StatefulWidget {
  const _CampaignsView({required this.accessToken, required this.repository});

  final String accessToken;
  final AdminRepository repository;

  @override
  State<_CampaignsView> createState() => _CampaignsViewState();
}

class _CampaignsViewState extends State<_CampaignsView> {
  final GlobalKey<AdminAsyncListState<AdminCampaign>> _queueKey =
      GlobalKey<AdminAsyncListState<AdminCampaign>>();
  final GlobalKey<AdminAsyncListState<AdminCampaign>> _activeKey =
      GlobalKey<AdminAsyncListState<AdminCampaign>>();
  bool _queue = true;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        AdminSectionHeader(
          title: 'Campaigns',
          subtitle: 'Verification and lifecycle oversight (campaigns.verify).',
          trailing: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('To verify')),
              ButtonSegment(value: false, label: Text('Active')),
            ],
            selected: {_queue},
            onSelectionChanged: (set) => setState(() => _queue = set.first),
          ),
        ),
        if (_queue)
          AdminAsyncList<AdminCampaign>(
            key: _queueKey,
            load: () => widget.repository.listCampaignQueue(
              access: widget.accessToken,
            ),
            emptyIcon: Icons.campaign_outlined,
            emptyTitle: 'Verification queue clear',
            emptyMessage: 'No campaigns are awaiting verification.',
            itemBuilder: (context, campaign) => _CampaignCard(
              campaign: campaign,
              queue: true,
              repository: widget.repository,
              accessToken: widget.accessToken,
              onChanged: () => _queueKey.currentState?.reload(),
            ),
          )
        else
          AdminAsyncList<AdminCampaign>(
            key: _activeKey,
            load: () => widget.repository.listCampaigns(
              access: widget.accessToken,
              status: 'ACTIVE',
            ),
            emptyIcon: Icons.campaign_outlined,
            emptyTitle: 'No active campaigns',
            emptyMessage: 'There are no live campaigns right now.',
            itemBuilder: (context, campaign) => _CampaignCard(
              campaign: campaign,
              queue: false,
              repository: widget.repository,
              accessToken: widget.accessToken,
              onChanged: () => _activeKey.currentState?.reload(),
            ),
          ),
      ],
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({
    required this.campaign,
    required this.queue,
    required this.repository,
    required this.accessToken,
    required this.onChanged,
  });

  final AdminCampaign campaign;
  final bool queue;
  final AdminRepository repository;
  final String accessToken;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(campaign.title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        '${campaign.ownerName.isEmpty ? 'No owner shown' : campaign.ownerName} · '
                        '${campaign.goalAmount.toStringAsFixed(0)} ${campaign.currency} goal',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                AdminStatusChip(status: campaign.status),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (campaign.progress / 100).clamp(0, 1),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${campaign.progress.toStringAsFixed(0)}% · '
              '${campaign.raisedAmount.toStringAsFixed(0)} ${campaign.currency} raised',
              style: theme.textTheme.bodySmall,
            ),
            if (queue && campaign.rejectionReason.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Rejected: ${campaign.rejectionReason}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            if (queue)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _decide(context, approve: false),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Reject'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _decide(context, approve: true),
                    icon: const Icon(Icons.verified_outlined, size: 18),
                    label: const Text('Approve'),
                  ),
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _lifecycle(context, close: false),
                    icon: const Icon(Icons.pause_outlined, size: 18),
                    label: const Text('Pause'),
                  ),
                  TextButton.icon(
                    onPressed: () => _lifecycle(context, close: true),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Close'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _decide(BuildContext context, {required bool approve}) async {
    final reason = await promptReason(
      context: context,
      title: approve ? 'Approve campaign' : 'Reject campaign',
      hint: approve ? 'Optional note (or 5+ chars)' : 'Reason for rejection (min 5 characters)',
    );
    if (reason == null && !approve) return;
    try {
      await repository.decideCampaign(
        access: accessToken,
        uid: campaign.uid,
        approve: approve,
        reason: reason ?? '',
      );
      if (!context.mounted) return;
      onChanged();
      showAdminMessage(context, approve ? 'Campaign approved.' : 'Campaign rejected.');
    } on Exception {
      if (!context.mounted) return;
      showAdminMessage(context, 'Could not update the campaign.');
    }
  }

  Future<void> _lifecycle(BuildContext context, {required bool close}) async {
    final reason = await promptReason(
      context: context,
      title: close ? 'Close campaign' : 'Pause campaign',
      hint: 'Reason (min 5 characters)',
    );
    if (reason == null) return;
    try {
      if (close) {
        await repository.closeCampaign(
          access: accessToken,
          uid: campaign.uid,
          reason: reason,
        );
      } else {
        await repository.pauseCampaign(
          access: accessToken,
          uid: campaign.uid,
          reason: reason,
        );
      }
      if (!context.mounted) return;
      onChanged();
      showAdminMessage(context, close ? 'Campaign closed.' : 'Campaign paused.');
    } on Exception {
      if (!context.mounted) return;
      showAdminMessage(context, 'Could not update the campaign.');
    }
  }
}