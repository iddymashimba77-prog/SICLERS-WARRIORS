import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import '../widgets/admin_widgets.dart';

/// Content CMS — News Articles (`content.news.manage`).
///
/// Full editorial workflow over `/api/admin/content/news/`: create-as-draft,
/// publish / unpublish / archive, feature (published only), delete (draft
/// only) and edit (draft/archived only). The backend enforces every rule —
/// the layer only surfaces what is valid per status.
class AdminNewsPage extends StatefulWidget {
  const AdminNewsPage({super.key, this.repository, this.accessToken});

  static const String routeName = '/admin/news-articles';

  final AdminRepository? repository;
  final String? accessToken;

  @override
  State<AdminNewsPage> createState() => _AdminNewsPageState();
}

class _AdminNewsPageState extends State<AdminNewsPage> {
  final GlobalKey<AdminAsyncListState<AdminNewsArticle>> _listKey =
      GlobalKey<AdminAsyncListState<AdminNewsArticle>>();
  late final AdminRepository _repository =
      widget.repository ?? AdminRepository(tokenStore: EphemeralTokenStore());
  String _status = '';

  String? get _token => widget.accessToken ?? SessionScope.controllerOf(context).accessToken;

  Future<List<AdminNewsArticle>> _load() async {
    final token = _token;
    if (token == null) return const [];
    return _repository.listNewsArticles(
      access: token,
      status: _status.isEmpty ? null : _status,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        AdminSectionHeader(
          title: tr('admin.newsArticles'),
          subtitle: tr('admin.newsSubtitle'),
          trailing: Wrap(
            spacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final filter in [
                ('', tr('admin.filter.all')),
                ('DRAFT', tr('admin.draft')),
                ('PUBLISHED', tr('admin.published')),
                ('ARCHIVED', tr('admin.archived')),
              ])
                ChoiceChip(
                  label: Text(filter.$2),
                  selected: _status == filter.$1,
                  onSelected: (_) {
                    setState(() => _status = filter.$1);
                    _listKey.currentState?.reload();
                  },
                ),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: Text(tr('admin.newArticle')),
                onPressed: () async {
                  final created = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => _NewsEditorPage(repository: _repository),
                    ),
                  );
                  if (created == true) _listKey.currentState?.reload();
                },
              ),
            ],
          ),
        ),
        AdminAsyncList<AdminNewsArticle>(
          key: _listKey,
          load: _load,
          emptyTitle: tr('admin.noArticles'),
          emptyMessage: tr('admin.nothingInState'),
          emptyIcon: Icons.newspaper_outlined,
          itemBuilder: (context, article) => _NewsCard(
            article: article,
            repository: _repository,
            token: _token ?? '',
            onChanged: () => _listKey.currentState?.reload(),
          ),
        ),
      ],
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({
    required this.article,
    required this.repository,
    required this.token,
    required this.onChanged,
  });

  final AdminNewsArticle article;
  final AdminRepository repository;
  final String token;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final published = article.status == 'PUBLISHED';
    final editable = article.status == 'DRAFT' || article.status == 'ARCHIVED';
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(article.title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (article.categoryLabel.isNotEmpty) article.categoryLabel,
                          if (article.authorName.isNotEmpty) article.authorName,
                          if (article.publishedAt != null)
                            (article.publishedAt ?? '').substring(0, 10),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (article.coverUrl.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: const [
                            Icon(Icons.image_outlined, size: 14),
                            SizedBox(width: 4),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (article.featured)
                  Tooltip(
                    message: tr('admin.featuredTooltip'),
                    child: const Icon(Icons.star, color: AppColors.warning, size: 20),
                  ),
                const SizedBox(width: AppSpacing.sm),
                AdminStatusChip(status: article.status),
              ],
            ),
            if (article.excerpt.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                article.excerpt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                if (!published)
                  FilledButton.tonalIcon(
                    onPressed: () => _setStatus(context, 'publish'),
                    icon: const Icon(Icons.publish, size: 18),
                    label: Text(tr('admin.publish')),
                  ),
                if (published)
                  OutlinedButton.icon(
                    onPressed: () => _setStatus(context, 'unpublish'),
                    icon: const Icon(Icons.unpublished_outlined, size: 18),
                    label: Text(tr('admin.unpublish')),
                  ),
                if (article.status != 'ARCHIVED')
                  OutlinedButton.icon(
                    onPressed: () => _setStatus(context, 'archive'),
                    icon: const Icon(Icons.archive_outlined, size: 18),
                    label: Text(tr('admin.archive')),
                  ),
                if (published)
                  IconButton.outlined(
                    tooltip: article.featured
                        ? tr('admin.removeFromFeatured')
                        : tr('admin.featureOnHome'),
                    icon: Icon(
                      article.featured ? Icons.star : Icons.star_border,
                      color: AppColors.warning,
                    ),
                    onPressed: () => _setFeatured(context),
                  ),
                if (editable)
                  TextButton.icon(
                    onPressed: () => _edit(context),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(tr('admin.edit')),
                  ),
                if (article.status == 'DRAFT')
                  TextButton.icon(
                    onPressed: () => _delete(context),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(tr('admin.delete')),
                  ),
              ],
            ),
            if (!editable && published)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  tr('admin.unpublishToEdit'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _setStatus(BuildContext context, String action) async {
    final doneKey = switch (action) {
      'publish' => 'admin.articlePublished',
      'unpublish' => 'admin.articleUnpublished',
      _ => 'admin.articleArchived',
    };
    try {
      await repository.setNewsStatus(access: token, uid: article.uid, action: action);
      if (!context.mounted) return;
      onChanged();
      showAdminMessage(context, tr(doneKey));
    } on Exception {
      if (!context.mounted) return;
      showAdminMessage(context, tr('admin.couldNotUpdateArticle'));
    }
  }

  Future<void> _setFeatured(BuildContext context) async {
    try {
      await repository.setNewsFeatured(
        access: token,
        uid: article.uid,
        featured: !article.featured,
      );
      if (!context.mounted) return;
      onChanged();
      showAdminMessage(
        context,
        tr(article.featured
            ? 'admin.removedFromFeatured'
            : 'admin.featuredOnHome'),
      );
    } on Exception {
      if (!context.mounted) return;
      showAdminMessage(context, tr('admin.couldNotUpdateFeatured'));
    }
  }

  Future<void> _edit(BuildContext context) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _NewsEditorPage(repository: repository, article: article),
      ),
    );
    if (saved == true) onChanged();
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await confirmAction(
      context: context,
      title: tr('admin.deleteArticleTitle'),
      message: tr('admin.deleteArticleBody').replaceAll('{title}', article.title),
      confirmLabel: tr('admin.delete'),
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await repository.deleteNewsArticle(access: token, uid: article.uid);
      if (!context.mounted) return;
      onChanged();
      showAdminMessage(context, tr('admin.articleDeleted'));
    } on Exception {
      if (!context.mounted) return;
      showAdminMessage(context, tr('admin.couldNotDeleteArticle'));
    }
  }
}

class _NewsEditorPage extends StatefulWidget {
  const _NewsEditorPage({required this.repository, this.article});

  final AdminRepository repository;
  final AdminNewsArticle? article;

  @override
  State<_NewsEditorPage> createState() => _NewsEditorPageState();
}

class _NewsEditorPageState extends State<_NewsEditorPage> {
  static const _categories = [
    'HEALTH', 'BLOOD', 'COMMUNITY', 'EDUCATION', 'EVENTS', 'ANNOUNCEMENTS', 'FUNDRAISING',
  ];
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.article?.title ?? '');
  late String _category = widget.article?.category ?? 'HEALTH';
  late final _excerpt = TextEditingController(text: widget.article?.excerpt ?? '');
  late final _body = TextEditingController(text: widget.article?.body ?? '');
  late final _tags = TextEditingController(text: widget.article?.tags.join(', ') ?? '');
  late final _coverUrl = TextEditingController(text: widget.article?.coverUrl ?? '');
  late final _coverAlt = TextEditingController(text: widget.article?.coverAlt ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _excerpt.dispose();
    _body.dispose();
    _tags.dispose();
    _coverUrl.dispose();
    _coverAlt.dispose();
    super.dispose();
  }

  String? get _token => SessionScope.controllerOf(context).accessToken;

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final tags = _tags.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    try {
      final token = _token;
      if (token == null) throw const FormatException();
      final target = widget.article;
      if (target == null) {
        await widget.repository.createNewsArticle(
          access: token,
          title: _title.text.trim(),
          category: _category,
          body: _body.text.trim(),
          excerpt: _excerpt.text.trim(),
          coverUrl: _coverUrl.text.trim(),
          coverAlt: _coverAlt.text.trim(),
          tags: tags,
        );
      } else {
        await widget.repository.updateNewsArticle(
          access: token,
          uid: target.uid,
          title: _title.text.trim(),
          category: _category,
          excerpt: _excerpt.text.trim(),
          body: _body.text.trim(),
          coverUrl: _coverUrl.text.trim(),
          coverAlt: _coverAlt.text.trim(),
          tags: tags,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Exception {
      if (!mounted) return;
      setState(() => _saving = false);
      showAdminMessage(context, tr('admin.couldNotSaveArticle'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.article == null
            ? tr('admin.newArticle')
            : tr('admin.editArticle')),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check, size: 18),
            label: Text(_saving ? tr('admin.saving') : tr('common.save')),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            TextFormField(
              controller: _title,
              decoration: InputDecoration(
                labelText: tr('admin.fieldTitle'),
                border: const OutlineInputBorder(),
              ),
              maxLength: 200,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? tr('admin.titleRequired') : null,
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: InputDecoration(
                labelText: tr('admin.category'),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final c in _categories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => _category = v ?? 'HEALTH',
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _excerpt,
              decoration: InputDecoration(
                labelText: tr('admin.excerpt'),
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
              maxLength: 500,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _body,
              decoration: InputDecoration(
                labelText: tr('admin.body'),
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
              maxLines: 8,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? tr('admin.bodyRequired') : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _tags,
              decoration: InputDecoration(
                labelText: tr('admin.tags'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _coverUrl,
              decoration: InputDecoration(
                labelText: tr('admin.coverUrl'),
                hintText: tr('admin.coverUrlHint'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _coverAlt,
              decoration: InputDecoration(
                labelText: tr('admin.coverAlt'),
                border: const OutlineInputBorder(),
              ),
              maxLength: 300,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              tr('admin.articlesDraftNote'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }
}

/// Content CMS — Announcements (`content.ticker.manage`).
class AdminTickerPage extends StatefulWidget {
  const AdminTickerPage({super.key, this.repository, this.accessToken});

  static const String routeName = '/admin/announcements';

  final AdminRepository? repository;
  final String? accessToken;

  @override
  State<AdminTickerPage> createState() => _AdminTickerPageState();
}

class _AdminTickerPageState extends State<AdminTickerPage> {
  final GlobalKey<AdminAsyncListState<AdminTickerAnnouncement>> _listKey =
      GlobalKey<AdminAsyncListState<AdminTickerAnnouncement>>();
  late final AdminRepository _repository =
      widget.repository ?? AdminRepository(tokenStore: EphemeralTokenStore());
  bool _onlyActive = false;

  String? get _token => widget.accessToken ?? SessionScope.controllerOf(context).accessToken;

  Future<List<AdminTickerAnnouncement>> _load() async {
    final token = _token;
    if (token == null) return const [];
    return _repository.listTicker(access: token, active: _onlyActive);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        AdminSectionHeader(
          title: tr('admin.nav.announcements'),
          subtitle: tr('admin.tickerSubtitle'),
          trailing: Wrap(
            spacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: Text(tr('admin.activeOnly')),
                selected: _onlyActive,
                onSelected: (v) {
                  setState(() => _onlyActive = v);
                  _listKey.currentState?.reload();
                },
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: Text(tr('admin.newAnnouncement')),
                onPressed: _showEditor,
              ),
            ],
          ),
        ),
        AdminAsyncList<AdminTickerAnnouncement>(
          key: _listKey,
          load: _load,
          emptyTitle: tr('admin.noAnnouncements'),
          emptyMessage: tr('admin.nothingHereYet'),
          emptyIcon: Icons.campaign_outlined,
          itemBuilder: (context, announcement) => _TickerCard(
            announcement: announcement,
            repository: _repository,
            token: _token ?? '',
            onChanged: () => _listKey.currentState?.reload(),
            onEdit: () => _showEditor(existing: announcement),
          ),
        ),
      ],
    );
  }

  Future<void> _showEditor({AdminTickerAnnouncement? existing}) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _TickerEditorDialog(repository: _repository, existing: existing),
    );
    if (changed == true) _listKey.currentState?.reload();
  }
}

class _TickerCard extends StatelessWidget {
  const _TickerCard({
    required this.announcement,
    required this.repository,
    required this.token,
    required this.onChanged,
    required this.onEdit,
  });

  final AdminTickerAnnouncement announcement;
  final AdminRepository repository;
  final String token;
  final VoidCallback onChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              value: announcement.isActive,
              onChanged: (active) => _setActive(context, active),
              title: Text(
                announcement.message,
                style: theme.textTheme.titleMedium,
              ),
              subtitle: Text(
                [
                  announcement.typeLabel.isEmpty
                      ? announcement.type
                      : announcement.typeLabel,
                  if (announcement.priority != 0)
                    '${tr('admin.priorityLabel')} ${announcement.priority}',
                  if (announcement.linkUrl.isNotEmpty) tr('admin.hasLink'),
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              secondary: AdminStatusChip(
                status: announcement.isActive ? 'ACTIVE' : 'INACTIVE',
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md),
              child: Text(
                _scheduleText(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(tr('admin.edit')),
                ),
                TextButton.icon(
                  onPressed: () => _delete(context),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(tr('admin.delete')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _scheduleText() {
    if (announcement.startAt == null && announcement.endAt == null) {
      return tr('admin.alwaysShown');
    }
    final parts = <String>[
      if (announcement.startAt != null)
        '${tr('admin.fromLabel')} ${announcement.startAt}',
      if (announcement.endAt != null)
        '${tr('admin.untilLabel')} ${announcement.endAt}',
    ];
    return '${tr('admin.scheduledLabel')} ${parts.join(' ')}';
  }

  Future<void> _setActive(BuildContext context, bool active) async {
    try {
      await repository.setTickerActive(access: token, uid: announcement.uid, active: active);
      if (!context.mounted) return;
      onChanged();
      showAdminMessage(
        context,
        tr(active
            ? 'admin.announcementActivated'
            : 'admin.announcementDeactivated'),
      );
    } on Exception {
      if (!context.mounted) return;
      showAdminMessage(context, tr('admin.couldNotUpdateAnnouncement'));
    }
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await confirmAction(
      context: context,
      title: tr('admin.deleteAnnouncementTitle'),
      message: tr('admin.deleteAnnouncementBody'),
      confirmLabel: tr('admin.delete'),
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await repository.deleteTicker(access: token, uid: announcement.uid);
      if (!context.mounted) return;
      onChanged();
      showAdminMessage(context, tr('admin.announcementDeleted'));
    } on Exception {
      if (!context.mounted) return;
      showAdminMessage(context, tr('admin.couldNotDeleteAnnouncement'));
    }
  }
}

class _TickerEditorDialog extends StatefulWidget {
  const _TickerEditorDialog({required this.repository, this.existing});

  final AdminRepository repository;
  final AdminTickerAnnouncement? existing;

  @override
  State<_TickerEditorDialog> createState() => _TickerEditorDialogState();
}

class _TickerEditorDialogState extends State<_TickerEditorDialog> {
  static const _types = [
    'INFO', 'URGENT', 'BLOOD', 'EVENT', 'DONATION', 'SUCCESS',
  ];
  final _formKey = GlobalKey<FormState>();
  late final _message = TextEditingController(text: widget.existing?.message ?? '');
  late String _type = widget.existing?.type ?? 'INFO';
  late final _link = TextEditingController(text: widget.existing?.linkUrl ?? '');
  late final _priority = TextEditingController(
    text: widget.existing == null ? '0' : '${widget.existing!.priority}',
  );
  late final _start = TextEditingController(text: widget.existing?.startAt ?? '');
  late final _end = TextEditingController(text: widget.existing?.endAt ?? '');
  late bool _active = widget.existing?.isActive ?? false;
  bool _saving = false;

  @override
  void dispose() {
    _message.dispose();
    _link.dispose();
    _priority.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  String? get _token => SessionScope.controllerOf(context).accessToken;

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final token = _token;
      if (token == null) throw const FormatException();
      final priority = int.tryParse(_priority.text.trim()) ?? 0;
      final start = _start.text.trim();
      final end = _end.text.trim();
      final existing = widget.existing;
      if (existing == null) {
        await widget.repository.createTicker(
          access: token,
          message: _message.text.trim(),
          type: _type,
          linkUrl: _link.text.trim(),
          isActive: _active,
          priority: priority,
          startAt: start.isEmpty ? null : start,
          endAt: end.isEmpty ? null : end,
        );
      } else {
        await widget.repository.updateTicker(
          access: token,
          uid: existing.uid,
          message: _message.text.trim(),
          type: _type,
          linkUrl: _link.text.trim(),
          isActive: _active,
          priority: priority,
          startAt: start.isEmpty ? null : start,
          endAt: end.isEmpty ? null : end,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Exception {
      if (!mounted) return;
      setState(() => _saving = false);
      showAdminMessage(context, tr('admin.couldNotSaveAnnouncement'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? tr('admin.newAnnouncement')
          : tr('admin.editAnnouncement')),
      scrollable: true,
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _message,
                decoration: InputDecoration(labelText: tr('admin.message')),
                maxLength: 240,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? tr('admin.messageRequired')
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: InputDecoration(labelText: tr('admin.type')),
                items: [
                  for (final t in _types)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => _type = v ?? 'INFO',
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _link,
                decoration:
                    InputDecoration(labelText: tr('admin.linkUrlOptional')),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _priority,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('admin.priorityHint')),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _start,
                decoration: InputDecoration(
                  labelText: tr('admin.startOptional'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _end,
                decoration: InputDecoration(
                  labelText: tr('admin.endOptional'),
                ),
              ),
              SwitchListTile(
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: Text(tr('admin.activeNow')),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(tr('common.cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? tr('admin.saving') : tr('common.save')),
        ),
      ],
    );
  }
}