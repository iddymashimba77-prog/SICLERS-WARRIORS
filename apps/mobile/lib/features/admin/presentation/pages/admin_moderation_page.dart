import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import '../widgets/admin_widgets.dart';

/// Community moderation (ADMIN-3) — GET /api/admin/community/reports/ + resolve
/// (RESOLVED/DISMISSED with optional content action) gated by community.moderate.
class AdminModerationPage extends StatelessWidget {
  const AdminModerationPage({super.key, this.repository, this.accessToken});

  static const String routeName = '/admin/moderation';

  final AdminRepository? repository;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.controllerOf(context);
    final token = accessToken ?? session.accessToken;
    if (token == null) return const Center(child: Text('Not signed in.'));
    return _ModerationView(
      accessToken: token,
      repository: repository ?? AdminRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class _ModerationView extends StatefulWidget {
  const _ModerationView({required this.accessToken, required this.repository});

  final String accessToken;
  final AdminRepository repository;

  @override
  State<_ModerationView> createState() => _ModerationViewState();
}

class _ModerationViewState extends State<_ModerationView> {
  final GlobalKey<AdminAsyncListState<AdminReport>> _listKey =
      GlobalKey<AdminAsyncListState<AdminReport>>();

  @override
  Widget build(BuildContext context) {
    return AdminAsyncList<AdminReport>(
      key: _listKey,
      load: () => widget.repository.listReports(access: widget.accessToken),
      emptyIcon: Icons.report_outlined,
      emptyTitle: 'No open reports',
      emptyMessage: 'There are no reports awaiting moderation.',
      itemBuilder: (context, report) => _ReportCard(
        report: report,
        repository: widget.repository,
        accessToken: widget.accessToken,
        onChanged: () => _listKey.currentState?.reload(),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.repository,
    required this.accessToken,
    required this.onChanged,
  });

  final AdminReport report;
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
                        '${report.targetType} report',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        report.reporterName.isEmpty
                            ? 'Reported content'
                            : 'Reported by ${report.reporterName}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                AdminStatusChip(status: report.status),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(report.reason, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              report.targetExists
                  ? '"${report.targetPreview.isEmpty ? 'Preview unavailable' : report.targetPreview}"'
                  : 'Target content no longer exists.',
              style: theme.textTheme.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (report.reviewNotes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Review notes: ${report.reviewNotes}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (report.status == 'OPEN' || report.status == 'IN_REVIEW') ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _resolve(context, status: 'DISMISSED'),
                    icon: const Icon(Icons.gpp_bad_outlined, size: 18),
                    label: const Text('Dismiss'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _resolve(context, status: 'RESOLVED'),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Resolve'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _resolve(BuildContext context, {required String status}) async {
    String action = 'NONE';
    String? notes;
    if (status == 'RESOLVED') {
      // Let the moderator pick a content action when upholding the report.
      final approach = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Resolve report'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop('NONE'),
              child: const Text('Keep content — just close the report'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop('HIDE'),
              child: const Text('Hide the reported content'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop('REMOVE'),
              child: const Text('Remove the reported content'),
            ),
          ],
        ),
      );
      if (approach == null || !context.mounted) return;
      action = approach;
      notes = await promptReason(
        context: context,
        title: 'Review notes',
        hint: 'Optional notes for the record (or 5+ chars)',
      );
      if (notes == null) return;
    }
    try {
      await repository.resolveReport(
        access: accessToken,
        id: report.id,
        status: status,
        action: action,
        reviewNotes: notes,
      );
      if (!context.mounted) return;
      onChanged();
      showAdminMessage(context,
          status == 'RESOLVED' ? 'Report resolved.' : 'Report dismissed.');
    } on Exception {
      if (!context.mounted) return;
      showAdminMessage(context, 'Could not resolve the report.');
    }
  }
}