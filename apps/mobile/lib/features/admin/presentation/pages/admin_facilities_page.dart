import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import '../widgets/admin_documents.dart';
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
    if (token == null) return Center(child: Text(tr('admin.notSignedIn')));
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
          title: tr('admin.nav.organizations'),
          subtitle: tr('admin.facilitiesSubtitle'),
          trailing: Wrap(
            spacing: 8,
            children: [
              for (final filter in [
                ('', tr('admin.filter.all')),
                ('pending', tr('admin.filter.pending')),
                ('verified', tr('admin.verified')),
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
          emptyTitle: tr('admin.noOrganizations'),
          emptyMessage: tr('admin.noFacilitiesMatch'),
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
                            ? '${tr('admin.facilityType')}: ${facility.facilityType.isEmpty ? '—' : facility.facilityType}'
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
            SubmittedDocumentsSection(
              documents: facility.verificationDocuments,
              repository: repository,
              accessToken: accessToken,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (facility.isVerified)
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  tr('admin.verifiedByAdmin'),
                  style: const TextStyle(fontSize: 12),
                ),
              )
            else
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
                    label: Text(tr('admin.approve')),
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
      title: tr(approve ? 'admin.approveFacility' : 'admin.rejectFacility'),
      hint: tr(approve ? 'admin.optionalNote' : 'admin.reasonRejection'),
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
      showAdminMessage(
        context,
        tr(approve ? 'admin.facilityApproved' : 'admin.facilityRejected'),
      );
    } on Exception {
      if (!context.mounted) return;
      showAdminMessage(context, tr('admin.couldNotUpdateFacility'));
    }
  }
}