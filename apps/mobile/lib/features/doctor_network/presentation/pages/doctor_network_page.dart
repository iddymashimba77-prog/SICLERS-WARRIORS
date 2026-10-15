import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/doctor_directory_repository.dart';
import '../../../chat/presentation/pages/conversation_list_page.dart';

/// Doctor Network destination: the verified care directory (`FR-CARE-001`).
///
/// The backend exposes the registry now, so this screen reads it instead of
/// describing an absent feature. Two rules hold:
///  * **Only verified providers appear.** `GET /doctors/` is already narrowed by
///    the server to approved and active professionals; there is no client-side
///    filter that could accidentally widen it.
///  * **No contact data, no licence numbers.** The projection the API returns is
///    the public subset, so a listing row cannot leak a private field.
class DoctorNetworkPage extends StatelessWidget {
  const DoctorNetworkPage({super.key, this.authController, this.repository});

  static const String routeName = '/doctors';

  /// Injected by widget tests; the routed instance resolves the shared session.
  final AuthController? authController;
  final DoctorDirectoryRepository? repository;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final token = (authController ?? SessionScope.controllerOf(context)).accessToken;
    if (token == null) {
      return Scaffold(
        appBar: AppBar(title: Text(s.tr('doctors.directory'))),
        body: Center(child: Text(s.tr('doctors.signInToBrowse'))),
      );
    }
    return DoctorDirectoryView(
      accessToken: token,
      repository: repository ??
          DoctorDirectoryRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

/// The registry list with a profession filter.
///
/// The filter is a server query parameter, not a client-side split: an
/// unrecognised value is rejected by the API, so the chips can only ever offer
/// what the server considers a profession.
class DoctorDirectoryView extends StatefulWidget {
  const DoctorDirectoryView({
    super.key,
    required this.accessToken,
    required this.repository,
    this.initialProfession,
  });

  final String accessToken;
  final DoctorDirectoryRepository repository;
  final String? initialProfession;

  @override
  State<DoctorDirectoryView> createState() => _DoctorDirectoryViewState();
}

class _DoctorDirectoryViewState extends State<DoctorDirectoryView> {
  List<VerifiedProfessional> _professionals = const [];
  Object? _error;
  bool _loading = true;
  late String? _filter = widget.initialProfession;

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
      final professionals = await widget.repository.list(
        access: widget.accessToken,
        professionalType: _filter,
      );
      if (!mounted) return;
      setState(() {
        _professionals = professionals;
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

  void _selectFilter(String? value) {
    if (_filter == value) return;
    setState(() => _filter = value);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.tr('doctors.directory')),
        actions: [
          IconButton(
            tooltip: s.tr('common.refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: LoadingView(),
              )
            else if (_error != null)
              ErrorRetryView(
                message: s.tr('doctors.directoryFailed'),
                onRetry: _load,
              )
            else if (_professionals.isEmpty)
              const _EmptyDirectory()
            else ...[
              _ProfessionFilter(selected: _filter, onSelected: _selectFilter),
              const SizedBox(height: AppSpacing.md),
              for (final professional in _professionals)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                      child: Icon(
                        iconForProfession(professional.professionalType),
                        color: AppColors.primary,
                      ),
                    ),
                    title: Text(professional.displayName),
                    subtitle: Text(professional.subtitle),
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.tr('doctors.directoryBody'), style: theme.textTheme.bodySmall),
                    const SizedBox(height: AppSpacing.lg),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pushNamed(
                        context,
                        ConversationListPage.routeName,
                      ),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: Text(s.tr('doctors.reachCareTeam')),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    s.tr('recordsPrivacy'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

IconData iconForProfession(String professionalType) => switch (professionalType) {
      'PSYCHOLOGIST' => Icons.psychology_outlined,
      'SOCIAL_SUPPORT' => Icons.support_agent_outlined,
      _ => Icons.medical_services_outlined,
    };

/// A registry role, as the server names it.
String professionLabel(AppLocalizations s, String professionalType) =>
    switch (professionalType) {
      'PSYCHOLOGIST' => s.tr('doctors.rolePsychologist'),
      'SOCIAL_SUPPORT' => s.tr('doctors.roleSocialSupport'),
      _ => s.tr('doctors.roleDoctor'),
    };

class _ProfessionFilter extends StatelessWidget {
  const _ProfessionFilter({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Wrap(
      spacing: AppSpacing.sm,
      children: [
        ChoiceChip(
          label: Text(s.tr('doctors.filterAll')),
          selected: selected == null,
          onSelected: (_) => onSelected(null),
        ),
        for (final type in DoctorDirectoryRepository.professionalTypes)
          ChoiceChip(
            label: Text(professionLabel(s, type)),
            selected: selected == type,
            onSelected: (_) => onSelected(type),
          ),
      ],
    );
  }
}

class _EmptyDirectory extends StatelessWidget {
  const _EmptyDirectory();

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Card(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            const Icon(
              Icons.verified_user_outlined,
              size: 56,
              color: AppColors.primary,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              s.tr('doctors.directoryTitle'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              s.tr('doctors.directoryEmpty'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}