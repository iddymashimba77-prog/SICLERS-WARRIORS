import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../../../../shared/widgets/dashboard_widgets.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/blood_repository.dart';
import 'blood_donation_page.dart';

/// Blood donor home (FRONTEND-3): donor profile, availability and the open
/// blood requests the backend makes visible to donors. Matching/compatibility
/// is computed by the backend only — never re-derived in Flutter.
class DonorHomePage extends StatelessWidget {
  const DonorHomePage({super.key, this.authController, this.repository});

  static const String routeName = '/donor-home';

  final AuthController? authController;
  final BloodRepository? repository;

  @override
  Widget build(BuildContext context) {
    final session = authController ?? SessionScope.controllerOf(context);
    final token = session.accessToken;
    if (token == null) {
      return const Scaffold(
        body: SafeArea(child: Center(child: Text(AppStrings.notSignedIn))),
      );
    }
    return Scaffold(
      appBar: AppTopBar(
        title: AppStrings.donorHome,
        avatarName: session.displayName,
      ),
      body: SafeArea(
        child: DonorHomeView(
          accessToken: token,
          repository: repository ?? BloodRepository(tokenStore: EphemeralTokenStore()),
        ),
      ),
    );
  }
}

class _DonorHomeData {
  const _DonorHomeData({
    required this.profile,
    required this.openRequests,
  });

  final BloodDonorProfile? profile;
  final List<BloodRequest> openRequests;
}

class DonorHomeView extends StatefulWidget {
  const DonorHomeView({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final BloodRepository repository;

  @override
  State<DonorHomeView> createState() => _DonorHomeViewState();
}

class _DonorHomeViewState extends State<DonorHomeView> {
  _DonorHomeData? _data;
  Object? _error;
  bool _loading = true;
  bool _savingAvailability = false;

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
      final results = await Future.wait<Object?>([
        widget.repository.getDonorProfile(access: widget.accessToken),
        widget.repository.listRequests(access: widget.accessToken),
      ]);
      final all = results[1] as List<BloodRequest>;
      if (!mounted) return;
      setState(() {
        _data = _DonorHomeData(
          profile: results[0] as BloodDonorProfile?,
          openRequests: all.where((r) => r.isOpen).toList(),
        );
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

  Future<void> _toggleAvailability(bool available) async {
    final profile = _data?.profile;
    if (profile == null) return;
    setState(() => _savingAvailability = true);
    try {
      await widget.repository.saveDonorProfile(
        access: widget.accessToken,
        bloodGroup: profile.bloodGroup,
        region: profile.region,
        city: profile.city,
        isAvailable: available,
      );
      if (!mounted) return;
      setState(() {
        _data = _DonorHomeData(
          profile: profile.copyWith(isAvailable: available),
          openRequests: _data!.openRequests,
        );
        _savingAvailability = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.donorSaved)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingAvailability = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.donorSaveFailed)),
      );
    }
  }

  Widget _availabilitySwitch(BloodDonorProfile profile) {
    return SwitchListTile(
      value: profile.isAvailable,
      onChanged: _savingAvailability ? null : _toggleAvailability,
      title: const Text(AppStrings.availableToDonate),
      subtitle: const Text(AppStrings.availabilityNote),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SkeletonListView(rows: 5);
    if (_error != null) {
      return ErrorRetryView(
        message: AppStrings.bloodLoadFailed,
        onRetry: _load,
      );
    }
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final profile = data.profile;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (profile == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      AppStrings.becomeDonor,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      AppStrings.donorEligibilityNote,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DonorProfilePage(
                            accessToken: widget.accessToken,
                            repository: widget.repository,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.bloodtype_outlined),
                      label: const Text(AppStrings.donorProfile),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.xs,
                    ),
                    child: Text(
                      AppStrings.myDonorProfile,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.bloodtype_outlined),
                    title: Text('${AppStrings.bloodGroup}: ${profile.bloodGroup}'),
                    subtitle: Text(
                      [profile.region, profile.city]
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                    ),
                  ),
                  ListTile(
                    leading: Icon(
                      profile.isVerified
                          ? Icons.verified_outlined
                          : Icons.verified_user_outlined,
                      color: profile.isVerified
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                    title: Text(
                      profile.isVerified
                          ? AppStrings.donorVerified
                          : AppStrings.donorEligibilityNote,
                    ),
                    subtitle: profile.donationCount > 0
                        ? Text('${profile.donationCount} ${AppStrings.donationHistory}')
                        : null,
                  ),
                  _availabilitySwitch(profile),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DonorProfilePage(
                            accessToken: widget.accessToken,
                            repository: widget.repository,
                            profile: profile,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text(AppStrings.editProfile),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(
            title: AppStrings.openBloodRequests,
            actionLabel: AppStrings.viewAll,
            onAction: () => Navigator.pushNamed(
              context,
              BloodDonationPage.routeName,
            ),
          ),
          if (data.openRequests.isEmpty)
            const EmptyStateView(
              message: AppStrings.noOpenRequests,
              icon: Icons.bloodtype_outlined,
            )
          else
            for (final r in data.openRequests.take(5))
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.bloodtype_outlined,
                    color: AppColors.emergency,
                  ),
                  title: Text(
                    '${AppStrings.bloodGroupNeeded}: ${r.bloodGroupNeeded}',
                  ),
                  subtitle: Text(
                    [
                      if (r.units > 0) '${r.units} units',
                      r.urgency,
                      r.location,
                    ].where((s) => s.isNotEmpty).join(' · '),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BloodRequestDetailPage(
                        accessToken: widget.accessToken,
                        repository: widget.repository,
                        request: r,
                      ),
                    ),
                  ),
                ),
              ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.lg),
          Text(
            AppStrings.donorProfileHelp,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}