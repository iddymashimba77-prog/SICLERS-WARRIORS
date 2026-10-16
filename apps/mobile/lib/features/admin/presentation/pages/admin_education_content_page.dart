import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import '../widgets/admin_widgets.dart';

/// Education content review queue (ADMIN-3) — GET /api/admin/education/content/
/// with approve/reject decisions (education.review). Rejection requires a reason.
class AdminEducationContentPage extends StatelessWidget {
  const AdminEducationContentPage({super.key, this.repository, this.accessToken});

  static const String routeName = '/admin/content-review';

  final AdminRepository? repository;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.controllerOf(context);
    final token = accessToken ?? session.accessToken;
    if (token == null) return Center(child: Text(tr('admin.notSignedIn')));
    return _ContentView(
      accessToken: token,
      repository: repository ?? AdminRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class _ContentView extends StatefulWidget {
  const _ContentView({required this.accessToken, required this.repository});

  final String accessToken;
  final AdminRepository repository;

  @override
  State<_ContentView> createState() => _ContentViewState();
}

class _ContentViewState extends State<_ContentView> {
  final GlobalKey<AdminAsyncListState<AdminContent>> _listKey =
      GlobalKey<AdminAsyncListState<AdminContent>>();
  String _status = 'IN_REVIEW';

  Future<List<AdminContent>> _load() => widget.repository.listContent(
        access: widget.accessToken,
        status: _status.isEmpty ? null : _status,
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        AdminSectionHeader(
          title: tr('admin.nav.contentReview'),
          subtitle: tr('admin.contentReviewSubtitle'),
          trailing: Wrap(
            spacing: 8,
            children: [
              for (final filter in [
                ('IN_REVIEW', tr('admin.inReview')),
                ('PUBLISHED', tr('admin.published')),
                ('REJECTED', tr('admin.rejected')),
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
        AdminAsyncList<AdminContent>(
          key: _listKey,
          load: _load,
          emptyTitle: tr('admin.nothingToReview'),
          emptyMessage: tr('admin.noContentState'),
          emptyIcon: Icons.article_outlined,
          itemBuilder: (context, content) => _ContentCard(
            content: content,
            repository: widget.repository,
            accessToken: widget.accessToken,
            onChanged: () => _listKey.currentState?.reload(),
          ),
        ),
      ],
    );
  }
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({
    required this.content,
    required this.repository,
    required this.accessToken,
    required this.onChanged,
  });

  final AdminContent content;
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
                      Text(content.title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (content.categoryName.isNotEmpty) content.categoryName,
                          if (content.authorName.isNotEmpty) content.authorName,
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                AdminStatusChip(status: content.status),
              ],
            ),
            if (content.rejectionReason.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${tr('admin.rejected')}: ${content.rejectionReason}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _preview(context),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: Text(tr('admin.preview')),
                ),
                const Spacer(),
                if (content.status != 'REJECTED')
                  TextButton.icon(
                    onPressed: () => _decide(context, approve: false),
                    icon: const Icon(Icons.close, size: 18),
                    label: Text(tr('admin.reject')),
                  ),
                if (content.status == 'IN_REVIEW')
                  FilledButton.icon(
                    onPressed: () => _decide(context, approve: true),
                    icon: const Icon(Icons.published_with_changes_outlined, size: 18),
                    label: Text(tr('admin.approve')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _preview(BuildContext context) {
    final plain = content.body
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(content.title),
        content: SizedBox(
          width: 560,
          child: SelectableText(
            plain.isEmpty ? tr('admin.noContentBody') : plain,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('common.close')),
          ),
        ],
      ),
    );
  }

  Future<void> _decide(BuildContext context, {required bool approve}) async {
    String? reason;
    if (!approve) {
      reason = await promptReason(
        context: context,
        title: tr('admin.rejectContent'),
        hint: tr('admin.reasonRejection'),
      );
      if (reason == null) return;
    }
    try {
      await repository.reviewContent(
        access: accessToken,
        uid: content.uid,
        decision: approve ? 'approve' : 'reject',
        reason: reason,
      );
      if (!context.mounted) return;
      onChanged();
      showAdminMessage(
        context,
        tr(approve ? 'admin.contentApproved' : 'admin.contentRejected'),
      );
    } on Exception {
      if (!context.mounted) return;
      showAdminMessage(context, tr('admin.couldNotReview'));
    }
  }
}