import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../../auth/domain/auth_types.dart';
import '../../data/medical_records_repository.dart';
import 'medical_record_detail_page.dart';
import 'medical_record_history_page.dart';
import '../../../../core/theme/app_shapes.dart';

/// The patient's chart (FR-MEDREC-001).
///
/// Reads `GET /medical-records/`, which the server has already narrowed to what
/// this account may see — consents, relationship, role. There is no client-side
/// filter and no client-side guess: if the API returns nothing, the honest
/// answer is the empty state, not a fabricated placeholder row.
class MedicalRecordsPage extends StatelessWidget {
  const MedicalRecordsPage({super.key, this.authController, this.repository});

  static const String routeName = '/records';

  /// Injected by widget tests; the routed instance resolves the shared session.
  final AuthController? authController;
  final MedicalRecordsRepository? repository;

  @override
  Widget build(BuildContext context) {
    final token = (authController ?? SessionScope.controllerOf(context)).accessToken;
    if (token == null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context).tr('medrec.title'))),
        body: Center(child: Text(AppLocalizations.of(context).tr('medrec.empty'))),
      );
    }
    return MedicalRecordsView(
      accessToken: token,
      repository: repository ??
          MedicalRecordsRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class MedicalRecordsView extends StatefulWidget {
  const MedicalRecordsView({
    super.key,
    required this.accessToken,
    required this.repository,
    this.initialStatus,
  });

  final String accessToken;
  final MedicalRecordsRepository repository;
  final String? initialStatus;

  @override
  State<MedicalRecordsView> createState() => _MedicalRecordsViewState();
}

class _MedicalRecordsViewState extends State<MedicalRecordsView> {
  static const _statusFilters = <String, String>{
    '': 'medrec.allStatuses',
    'DRAFT': 'medrec.status.draft',
    'ACTIVE': 'medrec.status.active',
    'REVOKED': 'medrec.status.revoked',
    'EXPIRED': 'medrec.status.expired',
  };

  List<MedicalRecordSummary> _items = const [];
  Object? _error;
  bool _loading = true;
  late String _status = widget.initialStatus ?? '';

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
      final items = await widget.repository.listRecords(
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

  String _messageFor(Object error) {
    final s = AppLocalizations.of(context);
    if (error is AuthException) {
      final message = error.message.trim();
      if (message.isNotEmpty && !message.contains('Exception')) return message;
    }
    return s.tr('medrec.loadFailed');
  }

  Future<void> _openRecord(MedicalRecordSummary item) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => MedicalRecordDetailPage(
          accessToken: widget.accessToken,
          repository: widget.repository,
          recordUid: item.uid,
          summary: item,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _openChartHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MedicalRecordHistoryPage(
          accessToken: widget.accessToken,
          repository: widget.repository,
          title: AppLocalizations.of(context).tr('medrec.chartHistory'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.tr('medrec.title')),
        actions: [
          IconButton(
            tooltip: s.tr('medrec.chartHistory'),
            onPressed: _loading ? null : _openChartHistory,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: s.tr('common.refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final entry in _statusFilters.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s.tr(entry.value)),
                      selected: _status == entry.key,
                      onSelected: (_) {
                        setState(() => _status = entry.key);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final s = AppLocalizations.of(context);
    if (_loading) return LoadingView(label: s.tr('medrec.loading'));
    if (_error != null) {
      return ErrorRetryView(message: _messageFor(_error!), onRetry: _load);
    }
    if (_items.isEmpty) {
      return EmptyStateView(message: s.tr('medrec.empty'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = _items[index];
          return Card(
            child: ListTile(
              title: Text(item.title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(
                    item.categoryName.isEmpty ? item.categoryCode : item.categoryName,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (item.facilityName.isNotEmpty)
                    Text(
                      item.facilityName,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (item.fileCount > 0)
                    Text(
                      s.tr(
                        'medrec.filesCount',
                        args: {'count': '${item.fileCount}'},
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
              isThreeLine: item.facilityName.isNotEmpty,
              trailing: _StatusChip(status: item.status),
              onTap: () => _openRecord(item),
            ),
          );
        },
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
      'ACTIVE' => (AppColors.success, s.tr('medrec.status.active')),
      'REVOKED' => (AppColors.emergency, s.tr('medrec.status.revoked')),
      'EXPIRED' => (AppColors.textSecondary, s.tr('medrec.status.expired')),
      _ => (AppColors.info, s.tr('medrec.status.draft')),
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

/// Small label row used by the detail page for author/facility facts.
class RecordFactRow extends StatelessWidget {
  const RecordFactRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}