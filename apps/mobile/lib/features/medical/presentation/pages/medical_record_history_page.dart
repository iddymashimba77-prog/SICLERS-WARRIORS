import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/domain/auth_types.dart';
import '../../data/medical_records_repository.dart';

/// Append-only chart history (FR-MEDREC-006).
///
/// With a [recordUid] this shows one record's trail; without it, the chart-wide
/// trail across every record the caller may read. Either way the entries come
/// from the server's append-only log — nothing is derived client-side, and
/// `details` is non-PHI by construction so it can be shown next to the record.
class MedicalRecordHistoryPage extends StatefulWidget {
  const MedicalRecordHistoryPage({
    super.key,
    required this.accessToken,
    required this.repository,
    required this.title,
    this.recordUid,
  });

  final String accessToken;
  final MedicalRecordsRepository repository;
  final String title;
  final String? recordUid;

  @override
  State<MedicalRecordHistoryPage> createState() => _MedicalRecordHistoryPageState();
}

class _MedicalRecordHistoryPageState extends State<MedicalRecordHistoryPage> {
  List<MedicalRecordEvent> _events = const [];
  Object? _error;
  bool _loading = true;

  bool get _isChartWide => (widget.recordUid ?? '').isEmpty;

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
      final events = _isChartWide
          ? await widget.repository.listChartHistory(access: widget.accessToken)
          : await widget.repository.listHistory(
              access: widget.accessToken,
              uid: widget.recordUid!,
            );
      if (!mounted) return;
      setState(() {
        _events = events;
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

  String _messageFor(Object error) {
    final s = AppLocalizations.of(context);
    if (error is AuthException) {
      final message = error.message.trim();
      if (message.isNotEmpty && !message.contains('Exception')) return message;
    }
    return s.tr('medrec.loadFailed');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final s = AppLocalizations.of(context);
    if (_loading) return LoadingView(label: s.tr('medrec.loading'));
    if (_error != null) {
      return ErrorRetryView(message: _messageFor(_error!), onRetry: _load);
    }
    if (_events.isEmpty) {
      return EmptyStateView(
        message: _isChartWide
            ? s.tr('medrec.chartHistoryEmpty')
            : s.tr('medrec.historyEmpty'),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: _events.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) => _EventTile(event: _events[index]),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final MedicalRecordEvent event;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final actor = event.actorName.trim().isEmpty || event.actorName == 'System'
        ? s.tr('medrec.historySystem')
        : s.tr('medrec.historyActor', args: {'actor': event.actorName});

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_iconFor(event.eventType), size: 20),
      title: Text(event.eventType, style: theme.textTheme.bodyMedium),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(actor, style: theme.textTheme.bodySmall),
          Text(event.occurredAt, style: theme.textTheme.bodySmall),
          if (event.fromStatus.isNotEmpty || event.toStatus.isNotEmpty)
            Text(
              '${event.fromStatus.isEmpty ? '—' : event.fromStatus} → '
              '${event.toStatus.isEmpty ? '—' : event.toStatus}',
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  static IconData _iconFor(String eventType) {
    final type = eventType.toLowerCase();
    if (type.contains('creat')) return Icons.note_add_outlined;
    if (type.contains('updat') || type.contains('edit')) return Icons.edit_outlined;
    if (type.contains('status')) return Icons.sync_alt;
    if (type.contains('visib') || type.contains('shar')) return Icons.share_outlined;
    if (type.contains('file') || type.contains('upload')) return Icons.attach_file;
    if (type.contains('download')) return Icons.download_outlined;
    if (type.contains('delet')) return Icons.delete_outline;
    return Icons.history;
  }
}