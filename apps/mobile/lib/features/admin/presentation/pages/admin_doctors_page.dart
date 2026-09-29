import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import '../widgets/admin_widgets.dart';

/// Doctor verification queue (ADMIN-3) — GET /api/admin/doctors/verification-queue/
/// with approve/reject + suspend actions (all audited, gated by doctors.verify).
class AdminDoctorsPage extends StatelessWidget {
  const AdminDoctorsPage({super.key, this.repository, this.accessToken});

  static const String routeName = '/admin/doctors';

  final AdminRepository? repository;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.controllerOf(context);
    final token = accessToken ?? session.accessToken;
    if (token == null) return const Center(child: Text('Not signed in.'));
    return _DoctorsView(
      accessToken: token,
      repository: repository ?? AdminRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class _DoctorsView extends StatefulWidget {
  const _DoctorsView({required this.accessToken, required this.repository});

  final String accessToken;
  final AdminRepository repository;

  @override
  State<_DoctorsView> createState() => _DoctorsViewState();
}

class _DoctorsViewState extends State<_DoctorsView> {
  final GlobalKey<AdminAsyncListState<AdminDoctor>> _listKey =
      GlobalKey<AdminAsyncListState<AdminDoctor>>();

  @override
  Widget build(BuildContext context) {
    return AdminAsyncList<AdminDoctor>(
      key: _listKey,
      load: () => widget.repository.listDoctorQueue(access: widget.accessToken),
      emptyIcon: Icons.medical_services_outlined,
      emptyTitle: 'Verification queue clear',
      emptyMessage: 'No doctors are awaiting verification.',
      itemBuilder: (context, doctor) => _DoctorCard(
        doctor: doctor,
        repository: widget.repository,
        accessToken: widget.accessToken,
        onChanged: () => _listKey.currentState?.reload(),
      ),
    );
  }
}

class _DoctorCard extends StatelessWidget {
  const _DoctorCard({
    required this.doctor,
    required this.repository,
    required this.accessToken,
    required this.onChanged,
  });

  final AdminDoctor doctor;
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
                        doctor.fullName.isEmpty ? doctor.email : doctor.fullName,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        doctor.email,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                AdminStatusChip(status: doctor.verificationStatus),
              ],
            ),
            if (doctor.specialty.isNotEmpty ||
                doctor.licenseNumber.isNotEmpty ||
                doctor.registrationBody.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _InfoRow(icon: Icons.school_outlined,
                  text: doctor.specialty),
              if (doctor.licenseNumber.isNotEmpty)
                _InfoRow(icon: Icons.badge_outlined, text: 'License ${doctor.licenseNumber}'),
              if (doctor.registrationBody.isNotEmpty)
                _InfoRow(icon: Icons.fact_check_outlined,
                    text: doctor.registrationBody),
            ],
            if (doctor.rejectionReason.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Rejected: ${doctor.rejectionReason}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _suspend(context),
                  icon: const Icon(Icons.block_outlined, size: 18),
                  label: const Text('Suspend'),
                ),
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
      title: approve ? 'Approve doctor' : 'Reject doctor',
      hint: approve ? 'Optional note (or 5+ chars)' : 'Reason for rejection (min 5 characters)',
    );
    if (reason == null && !approve) return;
    try {
      await repository.decideDoctor(
        access: accessToken,
        uid: doctor.uid,
        approve: approve,
        reason: reason ?? '',
      );
      if (!context.mounted) return;
      onChanged();
      showAdminMessage(context, approve ? 'Doctor approved.' : 'Doctor rejected.');
    } on Exception {
      if (!context.mounted) return;
      showAdminMessage(context, 'Could not update the doctor.');
    }
  }

  Future<void> _suspend(BuildContext context) async {
    final reason = await promptReason(
      context: context,
      title: 'Suspend doctor',
      hint: 'Reason for suspension (min 5 characters)',
    );
    if (reason == null) return;
    try {
      await repository.suspendDoctor(
        access: accessToken,
        uid: doctor.uid,
        reason: reason,
      );
      if (!context.mounted) return;
      onChanged();
      showAdminMessage(context, 'Doctor suspended.');
    } on Exception {
      if (!context.mounted) return;
      showAdminMessage(context, 'Could not suspend the doctor.');
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}