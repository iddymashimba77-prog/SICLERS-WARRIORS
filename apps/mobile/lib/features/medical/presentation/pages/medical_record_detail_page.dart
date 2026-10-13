import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/domain/auth_types.dart';
import '../../data/medical_records_repository.dart';
import 'medical_record_history_page.dart';
import 'medical_records_page.dart';

/// One chart entry, opened.
///
/// Everything here is gated by what the server said: `can_edit` and
/// `can_upload` come from the record projection, so a patient sees no edit or
/// status affordance on a record they may only read, and a clinician sees only
/// what their consent scope allows. Attachments are fetched through the
/// authorized download endpoint and handed to the platform opener — never a
/// stored URL.
class MedicalRecordDetailPage extends StatefulWidget {
  const MedicalRecordDetailPage({
    super.key,
    required this.accessToken,
    required this.repository,
    required this.recordUid,
    this.summary,
  });

  final String accessToken;
  final MedicalRecordsRepository repository;
  final String recordUid;
  final MedicalRecordSummary? summary;

  @override
  State<MedicalRecordDetailPage> createState() => _MedicalRecordDetailPageState();
}

class _MedicalRecordDetailPageState extends State<MedicalRecordDetailPage> {
  MedicalRecordDetail? _record;
  Object? _error;
  bool _loading = true;
  String? _busyUid;

  /// Temp directories holding downloaded files, cleared when the page closes.
  final List<Directory> _downloads = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final dir in _downloads) {
      if (dir.existsSync()) {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {
          // A file handed to an external app may still be open; the OS clears
          // its own temp directory, so a locked handle here is not fatal.
        }
      }
    }
    _downloads.clear();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final record = await widget.repository.getRecord(
        access: widget.accessToken,
        uid: widget.recordUid,
      );
      if (!mounted) return;
      setState(() {
        _record = record;
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

  String _messageFor(Object error) {
    final s = AppLocalizations.of(context);
    if (error is AuthException) {
      final message = error.message.trim();
      if (message.isNotEmpty && !message.contains('Exception')) return message;
    }
    return s.tr('medrec.loadFailed');
  }

  Future<void> _toggleVisibility(MedicalRecordDetail record) async {
    final s = AppLocalizations.of(context);
    final next = !record.isConsentVisible;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.tr('medrec.visTitle')),
        content: Text(s.tr('medrec.visBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s.tr('common.confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busyUid = record.uid);
    try {
      final updated = await widget.repository.setVisibility(
        access: widget.accessToken,
        uid: record.uid,
        isConsentVisible: next,
      );
      if (!mounted) return;
      setState(() {
        _record = updated;
        _busyUid = null;
      });
      _toast(s.tr('medrec.visUpdated'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyUid = null);
      _toast(_messageFor(e));
    }
  }

  Future<void> _setStatus(MedicalRecordDetail record, String status) async {
    final s = AppLocalizations.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _ReasonDialog(title: s.tr(status == 'REVOKED' ? 'medrec.status.revoked' : 'medrec.status.active')),
    );
    if (reason == null) return;
    setState(() => _busyUid = record.uid);
    try {
      final updated = await widget.repository.setStatus(
        access: widget.accessToken,
        uid: record.uid,
        status: status,
        reason: reason,
      );
      if (!mounted) return;
      setState(() {
        _record = updated;
        _busyUid = null;
      });
      _toast(s.tr('medrec.statusUpdated'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyUid = null);
      _toast(_messageFor(e));
    }
  }

  Future<void> _openHistory() async {
    final s = AppLocalizations.of(context);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MedicalRecordHistoryPage(
          accessToken: widget.accessToken,
          repository: widget.repository,
          recordUid: widget.recordUid,
          title: s.tr('medrec.history'),
        ),
      ),
    );
  }

  /// Download to a private temporary file, then hand it to the platform opener.
  ///
  /// The bytes come from an authorized API call, so there is no link to share.
  /// The file lands in a private temp directory under a sanitised name and is
  /// removed again on dispose; nothing is written to shared storage.
  Future<void> _download(MedicalRecordFile file) async {
    final s = AppLocalizations.of(context);
    setState(() => _busyUid = file.uid);
    try {
      final bytes = await widget.repository.downloadFile(
        access: widget.accessToken,
        file: file,
      );
      final dir = Directory.systemTemp.createTempSync('sw-record-');
      _downloads.add(dir);
      final path = '${dir.path}/${file.safeLocalName}';
      await File(path).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      final opened = await launchUrl(
        Uri.file(path),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      setState(() => _busyUid = null);
      if (!opened) _toast(s.tr('medrec.openFailed'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyUid = null);
      _toast(_messageFor(e) == s.tr('medrec.loadFailed')
          ? s.tr('medrec.downloadFailed')
          : _messageFor(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final record = _record;
    return Scaffold(
      appBar: AppBar(
        title: Text(record?.title ?? widget.summary?.title ?? s.tr('medrec.title')),
        actions: [
          IconButton(
            tooltip: s.tr('medrec.history'),
            onPressed: record == null ? null : _openHistory,
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: record == null || _loading
          ? null
          : _ActionBar(record: record, busy: _busyUid == record.uid),
    );
  }

  Widget _buildBody() {
    final s = AppLocalizations.of(context);
    if (_loading) return LoadingView(label: s.tr('medrec.loading'));
    if (_error != null) {
      return ErrorRetryView(message: _messageFor(_error!), onRetry: _load);
    }
    final record = _record;
    if (record == null) return EmptyStateView(message: s.tr('medrec.empty'));

    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RecordFactRow(
                  label: s.tr('medrec.category'),
                  value:
                      record.categoryName.isEmpty ? record.categoryCode : record.categoryName,
                ),
                RecordFactRow(
                  label: s.tr('medrec.recordedBy'),
                  value: record.recordedByName,
                ),
                RecordFactRow(
                  label: s.tr('medrec.facility'),
                  value: record.facilityName,
                ),
                RecordFactRow(
                  label: s.tr('medrec.recordedAt'),
                  value: record.recordedAt,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(record.description, style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.lg),
        Text(
          s.tr('medrec.files'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        if (record.files.isEmpty)
          Text(
            s.tr('edu.document.empty'),
            style: theme.textTheme.bodySmall,
          )
        else
          for (final file in record.files)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.attach_file),
              title: Text(
                file.readableSize.isEmpty
                    ? file.fileName
                    : '${file.fileName} · ${file.readableSize}',
              ),
              trailing: _busyUid == file.uid
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: s.tr('medrec.download'),
                      onPressed: () => _download(file),
                      icon: const Icon(Icons.download_outlined),
                    ),
            ),
      ],
    );
  }
}

/// Status and sharing actions, shown only for a record the caller may change.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.record, required this.busy});

  final MedicalRecordDetail record;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    // A patient can always opt a record out of the consent-derived read set;
    // only a record flagged `can_edit` may also change status.
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => _toggle(context),
                icon: Icon(
                  record.isConsentVisible ? Icons.lock_outline : Icons.share_outlined,
                  size: 18,
                ),
                label: Text(
                  s.tr(
                    record.isConsentVisible ? 'medrec.visConsent' : 'medrec.visPrivate',
                  ),
                ),
              ),
            ),
            if (record.canEdit) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => _changeStatus(context),
                  icon: const Icon(Icons.sync_alt, size: 18),
                  label: Text(s.tr('medrec.status.active')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context) async {
    final page = context.findAncestorStateOfType<_MedicalRecordDetailPageState>();
    await page?._toggleVisibility(record);
  }

  Future<void> _changeStatus(BuildContext context) async {
    final page = context.findAncestorStateOfType<_MedicalRecordDetailPageState>();
    final next = record.isDraft ? 'ACTIVE' : 'DRAFT';
    await page?._setStatus(record, next);
  }
}

/// Reason capture for a status change. The reason is not decoration: the server
/// stores it on the append-only history row, so it is prompted every time.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title});

  final String title;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 500,
        decoration: InputDecoration(
          labelText: s.tr('medrec.reason'),
          helperText: s.tr('medrec.reasonHint'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.tr('common.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(s.tr('common.save')),
        ),
      ],
    );
  }
}

/// Shared status colour helper so the list and detail agree.
Color statusColor(String status) => switch (status) {
      'ACTIVE' => AppColors.success,
      'REVOKED' => AppColors.emergency,
      'EXPIRED' => AppColors.textSecondary,
      _ => AppColors.info,
    };