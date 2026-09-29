import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import '../widgets/admin_kpi_card.dart';
import '../widgets/admin_widgets.dart';

/// Finance administration (ADMIN-3) — read-only ledger aggregates from
/// GET /api/admin/financial/summary/ and the donations ledger with audited
/// refunds (donations.refund).
class AdminFinancePage extends StatelessWidget {
  const AdminFinancePage({super.key, this.repository, this.accessToken});

  static const String routeName = '/admin/finance';

  final AdminRepository? repository;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.controllerOf(context);
    final token = accessToken ?? session.accessToken;
    if (token == null) return const Center(child: Text('Not signed in.'));
    return _FinanceView(
      accessToken: token,
      canRefund: session.permissions.contains('donations.refund'),
      repository: repository ?? AdminRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class _FinanceView extends StatefulWidget {
  const _FinanceView({
    required this.accessToken,
    required this.canRefund,
    required this.repository,
  });

  final String accessToken;
  final bool canRefund;
  final AdminRepository repository;

  @override
  State<_FinanceView> createState() => _FinanceViewState();
}

class _FinanceViewState extends State<_FinanceView> {
  final GlobalKey<AdminAsyncListState<AdminDonation>> _listKey =
      GlobalKey<AdminAsyncListState<AdminDonation>>();
  AdminFinancialSummary? _summary;
  bool _summaryLoading = true;
  bool _summaryError = false;
  bool _tabSummary = true;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _summaryLoading = true;
      _summaryError = false;
    });
    try {
      final summary =
          await widget.repository.financialSummary(access: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _summaryLoading = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _summaryError = true;
        _summaryLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        AdminSectionHeader(
          title: 'Finance',
          subtitle: 'Aggregates from confirmed ledger rows (donations.view).',
          trailing: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Summary')),
              ButtonSegment(value: false, label: Text('Ledger')),
            ],
            selected: {_tabSummary},
            onSelectionChanged: (set) => setState(() => _tabSummary = set.first),
          ),
        ),
        if (_tabSummary) _summarySection() else _ledgerSection(),
      ],
    );
  }

  Widget _summarySection() {
    if (_summaryLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_summaryError) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ErrorRetryView(
          message: 'The financial summary could not be loaded.',
          onRetry: _loadSummary,
        ),
      );
    }
    final s = _summary!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cols = constraints.maxWidth > 900 ? 3 : 2;
          return GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: cols,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            childAspectRatio: 1.6,
            children: [
              AdminKpiCard(
                icon: Icons.volunteer_activism_outlined,
                title: 'Confirmed Donations',
                value: '${s.confirmedDonationsTotal.toStringAsFixed(0)} TZS',
                description: '${s.confirmedDonationsCount} completed',
              ),
              AdminKpiCard(
                icon: Icons.currency_exchange_outlined,
                title: 'Refunded',
                value: '${s.refundedTotal.toStringAsFixed(0)} TZS',
                description: 'Processed refunds',
              ),
              AdminKpiCard(
                icon: Icons.pending_actions_outlined,
                title: 'Pending Donations',
                value: '${s.pendingDonationsCount}',
                description: 'Awaiting confirmation',
              ),
              AdminKpiCard(
                icon: Icons.campaign_outlined,
                title: 'Active Campaigns',
                value: '${s.activeCampaignsCount}',
                description: 'Live right now',
              ),
              AdminKpiCard(
                icon: Icons.event_available_outlined,
                title: 'Closed Campaigns',
                value: '${s.closedCampaignsCount}',
                description: 'Completed',
              ),
              AdminKpiCard(
                icon: Icons.verified_outlined,
                title: 'Verified Campaigns',
                value: '${s.verifiedCampaignsCount}',
                description: 'Checked by staff',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _ledgerSection() {
    return AdminAsyncList<AdminDonation>(
      key: _listKey,
      load: () => widget.repository.listDonations(access: widget.accessToken),
      emptyIcon: Icons.receipt_long_outlined,
      emptyTitle: 'No donations',
      emptyMessage: 'The donations ledger is empty.',
      itemBuilder: (context, donation) => Card(
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
                          '${donation.amount.toStringAsFixed(0)} ${donation.currency}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (donation.donorName.isNotEmpty) donation.donorName,
                            if (donation.campaignTitle.isNotEmpty)
                              donation.campaignTitle,
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  AdminStatusChip(status: donation.status),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: widget.canRefund && donation.isConfirmed
                    ? TextButton.icon(
                        onPressed: () => _refund(context, donation),
                        icon: const Icon(Icons.currency_exchange_outlined, size: 18),
                        label: const Text('Refund'),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refund(BuildContext context, AdminDonation donation) async {
    final reason = await promptReason(
      context: context,
      title: 'Refund donation',
      hint: 'Reason for the refund (min 5 characters)',
    );
    if (reason == null || !context.mounted) return;
    final amountController = TextEditingController();
    final amount = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Refund amount'),
        content: TextField(
          controller: amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: '0.00 ${donation.currency}',
            helperText:
                'Confirmed ${donation.amount.toStringAsFixed(0)} ${donation.currency}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(amountController.text.trim()),
            child: const Text('Refund'),
          ),
        ],
      ),
    );
    final parsed = double.tryParse(amount ?? '');
    if (parsed == null || parsed <= 0 || !context.mounted) return;
    final ok = await confirmAction(
      context: context,
      title: 'Confirm refund',
      message: 'Refund ${parsed.toStringAsFixed(0)} ${donation.currency} to this donor?',
      confirmLabel: 'Refund',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await widget.repository.refundDonation(
        access: widget.accessToken,
        uid: donation.uid,
        amount: parsed,
        reason: reason,
      );
      if (!context.mounted) return;
      _listKey.currentState?.reload();
      showAdminMessage(context, 'Refund recorded.');
    } on Exception {
      if (!context.mounted) return;
      showAdminMessage(context, 'Could not process the refund.');
    }
  }
}