import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/domain/auth_types.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/donations_repository.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../shared/widgets/signed_out_gate.dart';

const List<double> _presetAmounts = [5000, 10000, 25000, 50000];

/// Financial donations flow (approved FR-CAM-003..006, FR-PAY, DON-001..008).
///
/// Verified campaigns only (DON-001); tap-through detail (DON-002); preset +
/// custom TZS amounts and payment method (DON-003/004); the confirmation never
/// claims success client-side — "Donation initiated" (payment pending) is
/// clearly distinct from "Payment confirmed", which the app only shows after
/// the backend reports a webhook-verified COMPLETED state (DON-005). Status:
/// INITIATED→CONFIRMED | FAILED with retry only on PENDING/FAILED (DON-006);
/// history (DON-007) and a receipt only once confirmed (DON-008).
class DonationsPage extends StatelessWidget {
  const DonationsPage({
    super.key,
    this.authController,
    this.donationsRepository,
  });

  static const String routeName = '/donations';

  final AuthController? authController;
  final DonationsRepository? donationsRepository;

  @override
  Widget build(BuildContext context) {
    final token = (authController ?? SessionScope.controllerOf(context))
        .accessToken;
    if (token == null) {
      return const SignedOutGate();
    }
    return DonationsHomeView(
      accessToken: token,
      repository: donationsRepository ??
          DonationsRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class DonationsHomeView extends StatefulWidget {
  const DonationsHomeView({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final DonationsRepository repository;

  @override
  State<DonationsHomeView> createState() => _DonationsHomeViewState();
}

class _DonationsHomeViewState extends State<DonationsHomeView> {
  List<Campaign>? _campaigns;
  List<Donation> _donations = const [];
  Object? _campaignsError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _campaignsError = null;
    });
    List<Campaign>? campaigns;
    Object? campaignError;
    try {
      campaigns =
          await widget.repository.listCampaigns(access: widget.accessToken);
    } catch (e) {
      campaignError = e;
    }
    List<Donation> donations = const [];
    try {
      donations =
          await widget.repository.listDonations(access: widget.accessToken);
    } catch (_) {
      donations = const [];
    }
    if (!mounted) return;
    setState(() {
      _campaigns = campaigns;
      _campaignsError = campaignError;
      _donations = donations;
      _loading = false;
    });
  }

  Future<void> _openCampaign(Campaign campaign) async {
    final refreshed = await showModalBottomSheet<Campaign>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CampaignDetailSheet(
        accessToken: widget.accessToken,
        repository: widget.repository,
        campaign: campaign,
      ),
    );
    if (refreshed != null && mounted) await _load();
  }

  Future<void> _donate(Campaign campaign) async {
    final donation = await showModalBottomSheet<Donation>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DonateSheet(
        accessToken: widget.accessToken,
        repository: widget.repository,
        campaign: campaign,
      ),
    );
    if (donation == null || !mounted) return;
    if (donation.isInitiated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.donationInitiated)),
      );
      await _openStatus(donation);
    }
    await _load();
  }

  Future<void> _openStatus(Donation donation) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DonationStatusSheet(
        accessToken: widget.accessToken,
        repository: widget.repository,
        initial: donation,
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openReceipt(Donation donation) async {
    DonationReceipt? receipt;
    try {
      receipt = await widget.repository
          .getReceipt(access: widget.accessToken, uid: donation.uid);
    } on AuthException {
      receipt = null;
    } catch (_) {
      receipt = null;
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => _ReceiptDialog(receipt: receipt),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.financialDonations),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AppStrings.retry,
            onPressed: _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              AppStrings.verifiedCampaigns.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: LoadingView(),
              )
            else if (_campaignsError != null)
              ErrorRetryView(
                message: AppStrings.campaignsLoadFailed,
                onRetry: _load,
              )
            else if ((_campaigns ?? const []).isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: EmptyStateView(
                  message: AppStrings.noCampaigns,
                  icon: Icons.favorite_outline,
                ),
              )
            else
              for (final campaign in _campaigns!)
                _CampaignCard(
                  campaign: campaign,
                  onOpen: () => _openCampaign(campaign),
                  onDonate: () => _donate(campaign),
                ),
            const SizedBox(height: 24),
            Text(
              '${AppStrings.donationsHistory} · ${_donations.length}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 8),
            if (_donations.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: EmptyStateView(
                  message: AppStrings.noDonations,
                  icon: Icons.history,
                ),
              )
            else
              for (final donation in _donations)
                _DonationCard(
                  donation: donation,
                  onOpen: () => _openStatus(donation),
                  onReceipt:
                      donation.isConfirmed ? () => _openReceipt(donation) : null,
                ),
          ],
        ),
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({
    required this.campaign,
    required this.onOpen,
    required this.onDonate,
  });

  final Campaign campaign;
  final VoidCallback onOpen;
  final VoidCallback onDonate;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.verified,
                      color: AppColors.success, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      campaign.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Chip(label: Text(campaign.status.replaceAll('_', ' '))),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                campaign.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              _ProgressSummary(campaign: campaign),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: onDonate,
                  child: const Text(AppStrings.donateNow),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressSummary extends StatelessWidget {
  const _ProgressSummary({required this.campaign});

  final Campaign campaign;

  @override
  Widget build(BuildContext context) {
    final percent = (campaign.progress * 100).clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${campaign.raisedAmount.toStringAsFixed(0)} '
              '${AppStrings.donates} ${campaign.currency}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              '${percent.toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: AppShapes.xs,
          child: LinearProgressIndicator(
            value: percent / 100,
            minHeight: 8,
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),
        ),
      ],
    );
  }
}

class _DonationCard extends StatelessWidget {
  const _DonationCard({
    required this.donation,
    required this.onOpen,
    this.onReceipt,
  });

  final Donation donation;
  final VoidCallback onOpen;
  final VoidCallback? onReceipt;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: onOpen,
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          child: Icon(
            donation.isConfirmed
                ? Icons.check_circle
                : donation.isInitiated
                    ? Icons.schedule
                    : Icons.error_outline,
            color: donation.isConfirmed
                ? AppColors.success
                : donation.isInitiated
                    ? AppColors.secondary
                    : AppColors.emergency,
          ),
        ),
        title: Text(donation.campaignTitle),
        subtitle: Text(
          '${donation.displayStatus.replaceAll('_', ' ')} · '
          '${donation.amount.toStringAsFixed(0)} ${donation.currency}',
        ),
        trailing: onReceipt == null
            ? null
            : IconButton(
                icon: const Icon(Icons.receipt_long_outlined),
                tooltip: AppStrings.receiptTitle,
                onPressed: onReceipt,
              ),
      ),
    );
  }
}

/// DON-002: campaign detail — story, funds progress and verified org.
class _CampaignDetailSheet extends StatelessWidget {
  const _CampaignDetailSheet({
    required this.accessToken,
    required this.repository,
    required this.campaign,
  });

  final String accessToken;
  final DonationsRepository repository;
  final Campaign campaign;

  Future<void> _donate(BuildContext context) async {
    final donation = await showModalBottomSheet<Donation>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DonateSheet(
        accessToken: accessToken,
        repository: repository,
        campaign: campaign,
      ),
    );
    if (donation == null || !context.mounted) return;
    Navigator.of(context).pop(campaign);
    if (donation.isInitiated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.donationInitiated)),
      );
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _DonationStatusSheet(
          accessToken: accessToken,
          repository: repository,
          initial: donation,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.verified, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      campaign.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(campaign.description),
              const SizedBox(height: 12),
              _ProgressSummary(campaign: campaign),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 16),
                  const SizedBox(width: 6),
                  Text('${AppStrings.campaignOwner}: ${campaign.ownerName}'),
                ],
              ),
              if (campaign.createdAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${AppStrings.receiptDate}: ${campaign.createdAt}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _donate(context),
                  icon: const Icon(Icons.favorite_outline),
                  label: const Text(AppStrings.donateNow),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// DON-003/004: preset + custom TZS amount, payment method and consent to
/// share the donation reference before an idempotent POST.
class _DonateSheet extends StatefulWidget {
  const _DonateSheet({
    required this.accessToken,
    required this.repository,
    required this.campaign,
  });

  final String accessToken;
  final DonationsRepository repository;
  final Campaign campaign;

  @override
  State<_DonateSheet> createState() => _DonateSheetState();
}

class _DonateSheetState extends State<_DonateSheet> {
  double? _preset;
  String _provider = donationProviders.first;
  bool _consent = false;
  bool _submitting = false;
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  double get _amount {
    final parsed = double.tryParse(_custom.text.trim());
    if (parsed != null && parsed > 0) return parsed;
    return _preset ?? 0;
  }

  Future<void> _submit() async {
    if (_amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(AppStrings.donationAmountError)));
      return;
    }
    setState(() => _submitting = true);
    try {
      final donation = await widget.repository.initiateDonation(
        access: widget.accessToken,
        campaignUid: widget.campaign.uid,
        amount: _amount,
        provider: _provider,
      );
      if (!mounted) return;
      Navigator.of(context).pop(donation);
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError(AppStrings.donationActionFailed);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${AppStrings.donateNow} · ${widget.campaign.title}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              '${AppStrings.donationAmount} · min '
              '${widget.campaign.currency} 1',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final amount in _presetAmounts)
                  FilterChip(
                    label: Text(amount.toString()),
                    selected: _preset == amount,
                    onSelected: (_) => setState(() {
                      _preset = amount;
                      _custom.clear();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _custom,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: AppStrings.donationAmount,
                prefixText: 'TZS ',
              ),
              onChanged: (_) => setState(() => _preset = null),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _provider,
              decoration:
                  const InputDecoration(labelText: AppStrings.paymentMethod),
              items: [
                for (final provider in donationProviders)
                  DropdownMenuItem(
                    value: provider,
                    child: Text(_providerLabel(provider)),
                  ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _provider = v);
              },
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _consent,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setState(() => _consent = v ?? false),
              title: const Text(AppStrings.shareDonationRef),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _consent && !_submitting ? _submit : null,
                icon: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : const Icon(Icons.favorite_outline),
                label: Text(
                  _submitting
                      ? AppStrings.payoutPending
                      : AppStrings.confirmDonation,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _providerLabel(String provider) {
  switch (provider) {
    case 'M_PESA':
      return 'M-Pesa';
    case 'AIRTEL':
      return 'Airtel Money';
    case 'TIGO':
      return 'Tigo Pesa';
    case 'CLICKPESA':
      return 'ClickPesa';
    case 'SELCOM':
      return 'Selcom';
    default:
      return provider.replaceAll('_', ' ');
  }
}

/// DON-005/006: status sheet. Distinguishes initiated from confirmed; never
/// claims success client-side; retry only on PENDING/FAILED.
class _DonationStatusSheet extends StatefulWidget {
  const _DonationStatusSheet({
    required this.accessToken,
    required this.repository,
    required this.initial,
  });

  final String accessToken;
  final DonationsRepository repository;
  final Donation initial;

  @override
  State<_DonationStatusSheet> createState() => _DonationStatusSheetState();
}

class _DonationStatusSheetState extends State<_DonationStatusSheet> {
  late Donation _donation = widget.initial;
  bool _busy = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    final confirmed = _donation.isConfirmed;
    final failed = _donation.displayStatus == 'FAILED';
    return FractionallySizedBox(
      heightFactor: 0.6,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    confirmed
                        ? Icons.check_circle
                        : failed
                            ? Icons.cancel
                            : Icons.schedule,
                    color: confirmed
                        ? AppColors.success
                        : failed
                            ? AppColors.emergency
                            : AppColors.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _donation.displayStatus.replaceAll('_', ' '),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                confirmed
                    ? AppStrings.paymentConfirmed
                    : '${AppStrings.donationInitiatedBody}\n\n'
                        '${AppStrings.retryOnlyPendingOrFailed}',
              ),
              const SizedBox(height: 16),
              _InfoRow(
                label: AppStrings.receiptFor,
                value: _donation.campaignTitle,
              ),
              _InfoRow(
                label: AppStrings.donates,
                value:
                    '${_donation.amount.toStringAsFixed(0)} ${_donation.currency}',
              ),
              if (_donation.provider.isNotEmpty)
                _InfoRow(
                  label: AppStrings.paymentMethod,
                  value: _providerLabel(_donation.provider),
                ),
              _InfoRow(
                label: AppStrings.providerRefLabel,
                value: _donation.providerRef.isNotEmpty
                    ? _donation.providerRef
                    : _donation.redactedRef,
              ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(
                  _message!,
                  style: const TextStyle(color: AppColors.success),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() {
                                _busy = true;
                                _message = null;
                              });
                              try {
                                final updated = await widget.repository
                                    .getDonation(
                                  access: widget.accessToken,
                                  uid: _donation.uid,
                                );
                                if (!mounted) return;
                                setState(() {
                                  _donation = updated;
                                  _message = AppStrings.donationUpdated;
                                });
                              } on AuthException catch (e) {
                                _showError(e.message);
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            },
                      icon: const Icon(Icons.refresh),
                      label: const Text(AppStrings.checkStatus),
                    ),
                  ),
                  if (_donation.canRetry) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                setState(() {
                                  _busy = true;
                                  _message = null;
                                });
                                try {
                                  final updated = await widget.repository
                                      .retryDonation(
                                    access: widget.accessToken,
                                    donationUid: _donation.uid,
                                  );
                                  if (!mounted) return;
                                  setState(() {
                                    _donation = updated;
                                    _message = AppStrings.retryingDonation;
                                  });
                                } on AuthException catch (e) {
                                  _showError(e.message);
                                } finally {
                                  if (mounted) setState(() => _busy = false);
                                }
                              },
                        icon: const Icon(Icons.replay),
                        label: const Text(AppStrings.retryDonation),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

/// DON-008: donor-only receipt, only after the payment is confirmed.
class _ReceiptDialog extends StatelessWidget {
  const _ReceiptDialog({required this.receipt});

  final DonationReceipt? receipt;

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    return AlertDialog(
      title: const Text(AppStrings.receiptTitle),
      icon: const Icon(Icons.receipt_long, color: AppColors.success),
      content: r == null
          ? const Text(AppStrings.receiptNotAvailable)
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _InfoRow(label: AppStrings.receiptNumber, value: r.receiptNumber),
                  _InfoRow(label: AppStrings.receiptFor, value: r.campaignTitle),
                  _InfoRow(
                    label: AppStrings.receiptAmount,
                    value: '${r.amount.toStringAsFixed(0)} ${r.currency}',
                  ),
                  if (r.transactionRef.isNotEmpty)
                    _InfoRow(
                      label: AppStrings.transactionRef,
                      value: r.transactionRef,
                    ),
                  if (r.donatedAt != null)
                    _InfoRow(label: AppStrings.receiptDate, value: r.donatedAt!),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text(AppStrings.close),
        ),
      ],
    );
  }
}