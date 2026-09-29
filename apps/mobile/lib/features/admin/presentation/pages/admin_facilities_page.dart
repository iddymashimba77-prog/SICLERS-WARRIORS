import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import '../widgets/admin_widgets.dart';

/// Organization / facility administration (ADMIN-3) — GET /api/admin/facilities/
/// + verified/pending filter and the audited verify action (facilities.verify).
class AdminFacilitiesPage extends StatelessWidget {
  const AdminFacilitiesPage({super.key, this.repository, this.accessToken});

  static const String routeName = '/admin/organizations';

  final AdminRepository? repository;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.controllerOf(context);
    final token = accessToken ?? session.accessToken;
    if (token == null) return const Center(child: Text('Not signed in.'));
    return _FacilitiesView(
      accessToken: token,
      repository: repository ?? AdminRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class _FacilitiesView extends StatefulWidget {
  const _FacilitiesView({required this.accessToken, required this.repository});

  final String accessToken;
  final AdminRepository repository;

  @override
  State<_FacilitiesView> createState() => _FacilitiesViewState();
}

class _FacilitiesViewState extends State<_FacilitiesView> {
  final GlobalKey<AdminAsyncListState<AdminFacility>> _listKey =
      GlobalKey<AdminAsyncListState<AdminFacility>>();
  String _status = '';

  Future<List<AdminFacility>> _load() => widget.repository.listFacilities(
        access: widget.accessToken,
        status: _status.isEmpty ? null : _status,
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        AdminSectionHeader(
          title: 'Organizations',
          subtitle: 'Facilities and their operator accounts (facilities.verify).',
          trailing: Wrap(
            spacing: 8,
            children: [
              for (final filter in [
                ('', 'All'),
                ('pending', 'Pending'),
                ('verified', 'Verified'),
              ])
                ChoiceChip(
                  label: Text(filter.$2),
                  selected: _status == filter.$1,
                  onSelected: (_) {
                    setState(() => _status = filter.$1);
                    _listKey.currentState?.reload();
                  },
                ),
            ],
          ),
        ),
        AdminAsyncList<AdminFacility>(
          key: _listKey,
          load: _load,
          emptyTitle: 'No organizations',
          emptyMessage: 'No facilities match this filter.',
          emptyIcon: Icons.business_outlined,
          itemBuilder: (context, facility) => _FacilityCard(
            facility: facility,
            repository: widget.repository,
            accessToken: widget.accessToken,
            onChanged: () => _listKey.currentState?.reload(),
          ),
        ),
      ],
    );
  }
}

class _FacilityCard extends StatelessWidget {
  const _FacilityCard({
    required this.facility,
    required this.repository,
    required this.accessToken,
    required this.onChanged,
  });

  final AdminFacility facility;
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
                      Text(facility.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        facility.operatorEmail.isEmpty
                            ? 'Facility type: ${facility.facilityType.isEmpty ? '—' : facility.facilityType}'
                            : facility.operatorEmail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                AdminStatusChip(
                  status: facility.verificationStatus.isNotEmpty
                      ? facility.verificationStatus
                      : (facility.isVerified ? 'VERIFIED' : 'PENDING'),
                ),
              ],
            ),
            if (facility.address.isNotEmpty || facility.city.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                [facility.address, facility.city]
                    .where((s) => s.isNotEmpty)
                    .join(', '),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            if (facility.isVerified)
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Verified by administrator',
                  style: TextStyle(fontSize: 12),
                ),
              )
            else
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
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _decide(BuildContext context, {required bool approve}) async {
    final reason = await promptReason(
      context: context,
      title: approve ? 'Approve facility' : 'Reject facility',
      hint: approve ? 'Optional note (or 5+ chars)' : 'Reason for rejection (min 5 characters)',
    );
    if (reason == null && !approve) return;
    try {
      await repository.verifyFacility(
        access: accessToken,
        uid: facility.uid,
        approve: approve,
        reason: reason ?? '',
      );
      if (!context.mounted) return;
      onChanged();
      showAdminMessage(context, approve ? 'Facility approved.' : 'Facility rejected.');
    } on Exception {
      if (!context.mounted) return;
      showAdminMessage(context, 'Could not update the facility.');
    }
  }
}