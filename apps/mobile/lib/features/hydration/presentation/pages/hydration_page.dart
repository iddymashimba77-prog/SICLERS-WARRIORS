import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/banners/page_banner_catalog.dart';
import '../../../../shared/widgets/signed_out_gate.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/hydration_repository.dart';

/// Patient-only hydration tracker.
///
/// This surface records what the patient logs. It never assumes a daily fluid
/// target: the goal is optional and the copy points to the care team for
/// individual guidance.
class HydrationPage extends StatelessWidget {
  const HydrationPage({
    super.key,
    this.authController,
    this.repository,
  });

  static const String routeName = '/hydration';

  final AuthController? authController;
  final HydrationRepository? repository;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final session = authController ?? SessionScope.controllerOf(context);
    final token = session.accessToken;
    if (token == null) {
      return SignedOutGate(title: s.tr('hydration.title'));
    }
    return Scaffold(
      appBar: AppBar(title: Text(s.tr('hydration.title'))),
      body: SafeArea(
        child: HydrationView(
          accessToken: token,
          repository: repository ?? HydrationRepository(),
        ),
      ),
    );
  }
}

class HydrationView extends StatefulWidget {
  const HydrationView({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final HydrationRepository repository;

  @override
  State<HydrationView> createState() => _HydrationViewState();
}

class _HydrationViewState extends State<HydrationView> {
  HydrationDay? _day;
  Object? _error;
  bool _loading = true;
  bool _saving = false;

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
      final day = await widget.repository.fetchDay(access: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _day = day;
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

  Future<void> _add(int amountMl) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.repository.addIntake(
        access: widget.accessToken,
        amountMl: amountMl,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).tr('hydration.saved'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_message(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setGoal() async {
    final s = AppLocalizations.of(context);
    final initial = _day?.goalMl;
    final controller = TextEditingController(text: initial?.toString() ?? '');
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(s.tr('hydration.setGoal')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.tr('hydration.goalDialogBody')),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: const ValueKey('hydration-goal-input'),
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: s.tr('hydration.amountLabel'),
                    suffixText: s.tr('hydration.ml'),
                    errorText: error,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(s.tr('common.cancel')),
              ),
              FilledButton(
                key: const ValueKey('hydration-goal-save'),
                onPressed: () {
                  final parsed = int.tryParse(controller.text.trim());
                  if (parsed == null || parsed < 250 || parsed > 6000) {
                    setDialogState(() => error = s.tr('hydration.invalidGoal'));
                    return;
                  }
                  Navigator.of(ctx).pop(parsed);
                },
                child: Text(s.tr('common.save')),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    if (value == null) return;
    setState(() => _saving = true);
    try {
      await widget.repository.setGoal(
        access: widget.accessToken,
        goalMl: value,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.tr('hydration.goalSaved'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_message(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _customAmount() async {
    final s = AppLocalizations.of(context);
    final controller = TextEditingController();
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(s.tr('hydration.customAmount')),
            content: TextField(
              key: const ValueKey('hydration-custom-input'),
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: s.tr('hydration.intakeAmount'),
                suffixText: s.tr('hydration.ml'),
                errorText: error,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(s.tr('common.cancel')),
              ),
              FilledButton(
                key: const ValueKey('hydration-custom-save'),
                onPressed: () {
                  final parsed = int.tryParse(controller.text.trim());
                  if (parsed == null || parsed < 1 || parsed > 3000) {
                    setDialogState(
                      () => error = s.tr('hydration.invalidAmount'),
                    );
                    return;
                  }
                  Navigator.of(ctx).pop(parsed);
                },
                child: Text(s.tr('common.add')),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    if (value != null) await _add(value);
  }

  String _message(Object error) {
    if (error is Exception) {
      final text = error.toString();
      if (text.contains(': ')) return text.split(': ').last;
    }
    return AppLocalizations.of(context).tr('hydration.loadFailed');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _day == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.water_drop_outlined, size: 40),
              const SizedBox(height: AppSpacing.md),
              Text(s.tr('hydration.loadFailed'), textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                onPressed: _load,
                child: Text(s.tr('common.retry')),
              ),
            ],
          ),
        ),
      );
    }
    final day = _day!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          const PageBanner(
            page: BannerPage.healthDashboard,
            margin: EdgeInsets.only(bottom: AppSpacing.md),
          ),
          Text(
            s.tr('hydration.intro'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _SummaryCard(
            day: day,
            saving: _saving,
            onSetGoal: _setGoal,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            s.tr('hydration.addIntake'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final amount in const [150, 250, 500])
                FilledButton.tonalIcon(
                  key: ValueKey('hydration-add-$amount'),
                  onPressed: _saving ? null : () => _add(amount),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('$amount ${s.tr('hydration.ml')}'),
                ),
              OutlinedButton.icon(
                key: const ValueKey('hydration-custom'),
                onPressed: _saving ? null : _customAmount,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(s.tr('hydration.customAmount')),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            color: AppColors.lightBlue,
            borderColor: AppColors.blue.withValues(alpha: .18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: AppColors.blue, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    s.tr('hydration.disclaimer'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textPrimary,
                          height: 1.45,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Text(
                  s.tr('hydration.todayEntries'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Text(
                '${day.entries.length}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (day.entries.isEmpty)
            AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.water_drop_outlined, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.tr('hydration.empty'),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          s.tr('hydration.emptyBody'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (index, entry) in day.entries.indexed) ...[
                    ListTile(
                      key: ValueKey('hydration-entry-${entry.uid}'),
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.lightBlue,
                          borderRadius: AppShapes.small,
                        ),
                        child: const Icon(
                          Icons.water_drop_outlined,
                          color: AppColors.blue,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        '${entry.amountMl} ${s.tr('hydration.ml')}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      trailing: Text(
                        _timeLabel(entry.recordedAt),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (index < day.entries.length - 1)
                      const Divider(height: 1),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _timeLabel(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.day,
    required this.saving,
    required this.onSetGoal,
  });

  final HydrationDay day;
  final bool saving;
  final VoidCallback onSetGoal;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final goal = day.goalMl;
    final progress = (day.progressPct ?? 0) / 100;
    return AppCard(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: AppColors.lightBlue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.water_drop_outlined,
                  color: AppColors.blue,
                  size: 28,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.tr('hydration.today'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      goal == null
                          ? s.tr('hydration.noGoal')
                          : '${day.consumedMl} / $goal ${s.tr('hydration.ml')}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                key: const ValueKey('hydration-set-goal'),
                onPressed: saving ? null : onSetGoal,
                icon: const Icon(Icons.tune, size: 18),
                label: Text(
                  goal == null
                      ? s.tr('hydration.setGoal')
                      : s.tr('hydration.editGoal'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (goal == null)
            Text(
              s.tr('hydration.noGoalBody'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            )
          else ...[
            ClipRRect(
              borderRadius: AppShapes.pill,
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: AppColors.lightBlue,
                color: AppColors.blue,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(
                  '${day.consumedMl} ${s.tr('hydration.ml')} '
                  '${s.tr('hydration.consumed')}',
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                Text(
                  '${day.remainingMl ?? 0} ${s.tr('hydration.ml')} '
                  '${s.tr('hydration.remaining')}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
