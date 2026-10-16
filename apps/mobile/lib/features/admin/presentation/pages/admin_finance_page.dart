import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
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
    if (token == null) return Center(child: Text(tr('admin.notSignedIn')));
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
          title: tr('admin.nav.finance'),
          subtitle: tr('admin.financeSubtitle'),
          trailing: SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(tr('admin.summary'))),
              ButtonSegment(value: false, label: Text(tr('admin.ledger'))),
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
          message: tr('admin.financeError'),
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
                title: tr('admin.confirmedDonations'),
                value: '${s.confirmedDonationsTotal.toStringAsFixed(0)} TZS',
                description:
                    '${s.confirmedDonationsCount} ${tr('admin.completedWord')}',
              ),
              AdminKpiCard(
                icon: Icons.currency_exchange_outlined,
                title: tr('admin.refunded'),
                value: '${s.refundedTotal.toStringAsFixed(0)} TZS',
                description: tr('admin.processedRefunds'),
              ),
              AdminKpiCard(
                icon: Icons.pending_actions_outlined,
                title: tr('admin.pendingDonations'),
                value: '${s.pendingDonationsCount}',
                description: tr('admin.awaitingConfirmation'),
              ),
              AdminKpiCard(
                icon: Icons.campaign_outlined,
                title: tr('admin.activeCampaigns'),
                value: '${s.activeCampaignsCount}',
                description: tr('admin.liveRightNow'),
              ),
              AdminKpiCard(
                icon: Icons.event_available_outlined,
                title: tr('admin.closedCampaigns'),
                value: '${s.closedCampaignsCount}',
                description: tr('admin.completedLabel'),
              ),
              AdminKpiCard(
                icon: Icons.verified_outlined,
                title: tr('admin.verifiedCampaigns'),
                value: '${s.verifiedCampaignsCount}',
                description: tr('admin.checkedByStaff'),
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
      emptyTitle: tr('admin.noDonations'),
      emptyMessage: tr('admin.ledgerEmpty'),
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
                        label: Text(tr('admin.refund')),
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
      title: tr('admin.refundDonation'),
      hint: tr('admin.reasonRefund'),
    );
    if (reason == null || !context.mounted) return;
    final amountController = TextEditingController();
    final amount = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('admin.refundAmount')),
        content: TextField(
          controller: amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: '0.00 ${donation.currency}',
            helperText:
                '${tr('admin.confirmedLabel')} ${donation.amount.toStringAsFixed(0)} ${donation.currency}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(amountController.text.trim()),
            child: Text(tr('admin.refund')),
          ),
        ],
      ),
    );
    final parsed = double.tryParse(amount ?? '');
    if (parsed == null || parsed <= 0 || !context.mounted) return;
    final ok = await confirmAction(
      context: context,
      title: tr('admin.confirmRefund'),
      message: tr('admin.refundTo')
          .replaceAll('{amount}', parsed.toStringAsFixed(0))
          .replaceAll('{currency}', donation.currency),
      confirmLabel: tr('admin.refund'),
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
      showAdminMessage(context, tr('admin.refundRecorded'));
    } on Exception {
      if (!context.mounted) return;
      showAdminMessage(context, tr('admin.couldNotRefund'));
    }
  }
}