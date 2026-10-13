import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/domain/auth_types.dart';

import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../data/education_repository.dart';
import 'article_form_page.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../shared/widgets/signed_out_gate.dart';

/// Doctor-side authoring workspace for the Warrior Academy (FR-EDU-005).
///
/// Lists the signed-in doctor's own articles in every status — the public feed
/// only ever returns PUBLISHED rows, so this is a separate read — and lets
/// them write, edit, submit for review, delete a draft, and attach, replace or
/// remove the downloadable handout.
///
/// The server refuses every handout change while an article is PUBLISHED (the
/// public download would change without review), so `canChangeDocument`
/// mirrors that rule here instead of letting the user try and fail.
class DoctorEducationPage extends StatelessWidget {
  const DoctorEducationPage({super.key, this.authController, this.repository});

  static const String routeName = '/daktari/elimu';

  /// Injected by widget tests; the routed instance resolves the shared session.
  final AuthController? authController;
  final EducationRepository? repository;

  @override
  Widget build(BuildContext context) {
    final token = (authController ?? SessionScope.controllerOf(context)).accessToken;
    if (token == null) {
      return const SignedOutGate();
    }
    return DoctorEducationView(
      accessToken: token,
      repository: repository ?? EducationRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class DoctorEducationView extends StatefulWidget {
  const DoctorEducationView({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final EducationRepository repository;

  @override
  State<DoctorEducationView> createState() => _DoctorEducationViewState();
}

class _DoctorEducationViewState extends State<DoctorEducationView> {
  /// Status -> localization key, so the filter row is localised too.
  static const _statusFilters = <String, String>{
    '': 'edu.mine.allStatuses',
    'DRAFT': 'edu.status.draft',
    'IN_REVIEW': 'edu.status.inReview',
    'PUBLISHED': 'edu.status.published',
    'REJECTED': 'edu.status.rejected',
    'ARCHIVED': 'edu.status.archived',
  };

  List<EducationalContent> _items = const [];
  Object? _error;
  bool _loading = true;
  String _status = '';
  /// Uid whose upload is in flight, so only that row shows a spinner.
  String? _busyUid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.repository.listMyContent(
        access: widget.accessToken,
        status: _status.isEmpty ? null : _status,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Prefer the repository's own message (unsupported type, too large, expired
  /// token) over a blanket "could not update" — the user needs to know which
  /// file to pick instead.
  String _messageFor(Object error, [String fallbackKey = 'edu.document.failed']) {
    final fallback = AppLocalizations.of(context).tr(fallbackKey);
    if (error is! AuthException) return fallback;
    final message = error.message.trim();
    if (message.isNotEmpty && !message.contains('Exception')) return message;
    return fallback;
  }

  /// One action in flight at a time, tracked per uid so only the row that is
  /// being submitted or deleted shows a spinner.
  Future<void> _withBusy(String uid, Future<void> Function() action) async {
    setState(() => _busyUid = uid);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busyUid = null);
    }
  }

  Future<void> _openComposer({EducationalContent? article}) async {
    final s = AppLocalizations.of(context);
    if (article != null && !article.canEdit) {
      _toast(s.tr('edu.author.editLocked'));
      return;
    }
    final navigator = Navigator.of(context);
    final changed = await navigator.push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ArticleFormPage(
          accessToken: widget.accessToken,
          repository: widget.repository,
          article: article,
        ),
      ),
    );
    // Confirm on this page, which stays mounted after the pop. Re-check
    // `mounted`: the doctor may have left the workspace while composing.
    if (changed == true && mounted) {
      _toast(s.tr(article == null ? 'edu.author.saved' : 'edu.author.updated'));
      await _load();
    }
  }

  Future<void> _confirmSubmit(EducationalContent item) async {
    final s = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.tr('edu.author.submitTitle')),
        content: Text(s.tr('edu.author.submitBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s.tr('edu.author.submit')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _withBusy(item.uid, () async {
      try {
        await widget.repository.submitContent(
          access: widget.accessToken,
          uid: item.uid,
        );
        if (!mounted) return;
        _toast(s.tr('edu.author.submitted'));
        await _load();
      } catch (e) {
        if (!mounted) return;
        _toast(_messageFor(e, 'edu.author.submitFailed'));
      }
    });
  }

  Future<void> _confirmDelete(EducationalContent item) async {
    final s = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.tr('edu.author.deleteTitle')),
        content: Text(s.tr('edu.author.deleteBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.tr('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s.tr('edu.author.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _withBusy(item.uid, () async {
      try {
        await widget.repository.deleteContent(
          access: widget.accessToken,
          uid: item.uid,
        );
        if (!mounted) return;
        _toast(s.tr('edu.author.deleted'));
        await _load();
      } catch (e) {
        if (!mounted) return;
        _toast(_messageFor(e, 'edu.author.deleteFailed'));
      }
    });
  }

  Future<void> _pickAndUpload(EducationalContent item) async {
    final s = AppLocalizations.of(context);
    List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: DocumentUpload.allowedExtensions,
      );
    } catch (e) {
      if (mounted) _toast(_messageFor(e));
      return;
    }
    if (picked.isEmpty) return; // user cancelled
    final file = picked.single;
    final path = file.path;
    // Some platforms hand back bytes without a path (web, iOS via a provider);
    // this client only uploads from a path, so say so rather than failing oddly.
    if (path == null) {
      _toast(s.tr('edu.document.noPath'));
      return;
    }

    final upload = DocumentUpload(
      path: path,
      filename: file.name,
      // file_picker 13 reports length lazily; read it so the pre-flight size
      // check does not have to trust the platform's answer.
      sizeBytes: await file.length() ?? 0,
    );
    final rejection = upload.rejectionReason;
    if (rejection != null) {
      // Checked on-device first: there is no sense streaming 20 MB to a server
      // that will refuse it on the extension.
      _toast(rejection);
      return;
    }

    setState(() => _busyUid = item.uid);
    try {
      await widget.repository.uploadDocument(
        access: widget.accessToken,
        uid: item.uid,
        upload: upload,
      );
      if (!mounted) return;
      _toast(AppLocalizations.of(context).tr('edu.document.attached'));
      await _load();
    } catch (e) {
      if (mounted) _toast(_messageFor(e));
    } finally {
      if (mounted) setState(() => _busyUid = null);
    }
  }

  Future<void> _confirmRemove(EducationalContent item) async {
    final s = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.tr('edu.document.removeTitle')),
        content: Text(s.tr('edu.document.removeBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(s.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(s.tr('edu.document.remove')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busyUid = item.uid);
    try {
      await widget.repository.removeDocument(
        access: widget.accessToken,
        uid: item.uid,
      );
      if (!mounted) return;
      _toast(s.tr('edu.document.removed'));
      await _load();
    } catch (e) {
      if (mounted) _toast(_messageFor(e));
    } finally {
      if (mounted) setState(() => _busyUid = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.tr('edu.mine.title')),
        actions: [
          IconButton(
            tooltip: s.tr('common.refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: s.tr('edu.author.new'),
            onPressed: () => _openComposer(),
            icon: const Icon(Icons.note_add_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _openComposer(),
        icon: const Icon(Icons.add),
        label: Text(s.tr('edu.author.new')),
      ),
      body: Column(
        children: [
          _FilterBar(
            value: _status,
            labelKeys: _statusFilters,
            onChanged: (next) {
              setState(() => _status = next);
              _load();
            },
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final s = AppLocalizations.of(context);
    if (_loading) return const LoadingView();
    if (_error != null) {
      return ErrorRetryView(message: _messageFor(_error!), onRetry: _load);
    }
    if (_items.isEmpty) {
      return EmptyStateView(message: s.tr('edu.mine.empty'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _ArticleCard(
          item: _items[index],
          busy: _busyUid == _items[index].uid,
          onAttach: () => _pickAndUpload(_items[index]),
          onRemove: () => _confirmRemove(_items[index]),
          onEdit: () => _openComposer(article: _items[index]),
          onSubmit: () => _confirmSubmit(_items[index]),
          onDelete: () => _confirmDelete(_items[index]),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.value,
    required this.labelKeys,
    required this.onChanged,
  });

  final String value;
  final Map<String, String> labelKeys;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          for (final entry in labelKeys.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(s.tr(entry.value)),
                selected: value == entry.key,
                onSelected: (_) => onChanged(entry.key),
              ),
            ),
        ],
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({
    required this.item,
    required this.busy,
    required this.onAttach,
    required this.onRemove,
    required this.onEdit,
    required this.onSubmit,
    required this.onDelete,
  });

  final EducationalContent item;
  final bool busy;
  final VoidCallback onAttach;
  final VoidCallback onRemove;
  final VoidCallback onEdit;
  final VoidCallback onSubmit;
  final VoidCallback onDelete;

  Future<void> _openHandout(BuildContext context) async {
    final url = item.documentUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    final s = AppLocalizations.of(context);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.tr('edu.document.noApp'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                      Text(item.title, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        item.category.name.isEmpty
                            ? AppStrings.allCategories
                            : item.category.name,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _StatusChip(status: item.status),
              ],
            ),
            const SizedBox(height: 12),
            _HandoutSection(
              item: item,
              busy: busy,
              onAttach: onAttach,
              onRemove: onRemove,
              onOpen: () => _openHandout(context),
            ),
            const SizedBox(height: 10),
            _LifecycleActions(
              item: item,
              busy: busy,
              onEdit: onEdit,
              onSubmit: onSubmit,
              onDelete: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// The status-dependent author actions for one article.
///
/// Each button appears only when the server would accept it — `canEdit`,
/// `canSubmit` and `canDelete` mirror `education.models.EDITABLE_STATUSES`,
/// `SUBMITTABLE_STATUSES` and the draft-only delete rule — so the doctor is
/// never offered an action the server will refuse. An article that is neither
/// editable nor submittable shows why, rather than an empty row.
class _LifecycleActions extends StatelessWidget {
  const _LifecycleActions({
    required this.item,
    required this.busy,
    required this.onEdit,
    required this.onSubmit,
    required this.onDelete,
  });

  final EducationalContent item;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onSubmit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final spinner = const SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
    if (item.isPublished) {
      return Text(
        s.tr('edu.author.editLocked'),
        style: theme.textTheme.bodySmall,
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (item.canEdit)
          OutlinedButton.icon(
            onPressed: busy ? null : onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(s.tr('common.edit')),
          ),
        if (item.canSubmit)
          FilledButton.icon(
            onPressed: busy ? null : onSubmit,
            icon: busy ? spinner : const Icon(Icons.send, size: 18),
            label: Text(s.tr('edu.author.submit')),
          ),
        if (item.canDelete)
          TextButton.icon(
            onPressed: busy ? null : onDelete,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(s.tr('edu.author.delete')),
          ),
      ],
    );
  }
}

class _HandoutSection extends StatelessWidget {
  const _HandoutSection({
    required this.item,
    required this.busy,
    required this.onAttach,
    required this.onRemove,
    required this.onOpen,
  });

  final EducationalContent item;
  final bool busy;
  final VoidCallback onAttach;
  final VoidCallback onRemove;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppLocalizations.of(context);
    final attached = item.hasDocument;
    final editable = item.canChangeDocument;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.06),
        borderRadius: AppShapes.medium,
        border: Border.all(color: AppColors.border.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                s.tr('edu.document.label'),
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (attached)
            InkWell(
              onTap: onOpen,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      item.readableDocumentSize.isEmpty
                          ? item.documentName
                          : '${item.documentName} · ${item.readableDocumentSize}',
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.open_in_new, size: 15),
                ],
              ),
            )
          else
            Text(
              s.tr('edu.document.empty'),
              style: theme.textTheme.bodySmall,
            ),
          if (editable) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : onAttach,
                  icon: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(attached ? Icons.swap_horiz : Icons.attach_file),
                  label: Text(
                    s.tr(attached ? 'edu.document.replace' : 'edu.document.attach'),
                  ),
                ),
                if (attached)
                  TextButton.icon(
                    onPressed: busy ? null : onRemove,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(s.tr('edu.document.remove')),
                  ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              s.tr('edu.document.locked'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final (color, label) = switch (status) {
      'PUBLISHED' => (AppColors.success, s.tr('edu.status.published')),
      'IN_REVIEW' => (AppColors.warning, s.tr('edu.status.inReview')),
      'REJECTED' => (AppColors.emergency, s.tr('edu.status.rejected')),
      'ARCHIVED' => (AppColors.textSecondary, s.tr('edu.status.archived')),
      _ => (AppColors.info, s.tr('edu.status.draft')),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppShapes.pill,
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}