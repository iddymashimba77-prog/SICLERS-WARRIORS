import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import '../widgets/admin_widgets.dart';

/// Blood request verification queue (ADMIN-3) — GET
/// /api/blood/requests/verification-queue/ + verify/reject actions
/// (blood_requests.verify).
class AdminBloodRequestsPage extends StatelessWidget {
  const AdminBloodRequestsPage({super.key, this.repository, this.accessToken});

  static const String routeName = '/admin/blood-requests';

  final AdminRepository? repository;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.controllerOf(context);
    final token = accessToken ?? session.accessToken;
    if (token == null) return Center(child: Text(tr('admin.notSignedIn')));
    return _BloodView(
      accessToken: token,
      repository: repository ?? AdminRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class _BloodView extends StatefulWidget {
  const _BloodView({required this.accessToken, required this.repository});

  final String accessToken;
  final AdminRepository repository;

  @override
  State<_BloodView> createState() => _BloodViewState();
}

class _BloodViewState extends State<_BloodView> {
  final GlobalKey<AdminAsyncListState<AdminBloodRequest>> _listKey =
      GlobalKey<AdminAsyncListState<AdminBloodRequest>>();

  @override
  Widget build(BuildContext context) {
    return AdminAsyncList<AdminBloodRequest>(
      key: _listKey,
      load: () => widget.repository.listBloodQueue(access: widget.accessToken),
      emptyIcon: Icons.bloodtype_outlined,
      emptyTitle: tr('admin.queueClear'),
      emptyMessage: tr('admin.noBloodAwaiting'),
      itemBuilder: (context, request) => _BloodCard(
        request: request,
        repository: widget.repository,
        accessToken: widget.accessToken,
        onChanged: () => _listKey.currentState?.reload(),
      ),
    );
  }
}

class _BloodCard extends StatelessWidget {
  const _BloodCard({
    required this.request,
    required this.repository,
    required this.accessToken,
    required this.onChanged,
  });

  final AdminBloodRequest request;
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
                      Text(
                        '${request.bloodGroupNeeded} · ${request.units} ${tr('admin.units')}',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (request.urgency.isNotEmpty) request.urgency,
                          if (request.facilityName.isNotEmpty) request.facilityName,
                          if (request.location.isNotEmpty) request.location,
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                AdminStatusChip(status: request.status),
              ],
            ),
            if (request.creatorEmail.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${tr('admin.requestedBy')} ${request.creatorEmail}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (request.reason.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                request.reason,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _decide(context, approve: false),
                  icon: const Icon(Icons.close, size: 18),
                  label: Text(tr('admin.reject')),
                ),
                FilledButton.icon(
                  onPressed: () => _decide(context, approve: true),
                  icon: const Icon(Icons.verified_outlined, size: 18),
                  label: Text(tr('admin.verify')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _decide(BuildContext context, {required bool approve}) async {
    String? reason;
    if (!approve) {
      reason = await promptReason(
        context: context,
        title: tr('admin.rejectBloodRequest'),
        hint: tr('admin.reasonRejection'),
      );
      if (reason == null) return;
    }
    try {
      await repository.decideBloodRequest(
        access: accessToken,
        uid: request.uid,
        approve: approve,
        reason: reason,
      );
      if (!context.mounted) return;
      onChanged();
      showAdminMessage(
        context,
        tr(approve ? 'admin.requestVerified' : 'admin.requestRejected'),
      );
    } on Exception {
      if (!context.mounted) return;
      showAdminMessage(context, tr('admin.couldNotUpdateRequest'));
    }
  }
}