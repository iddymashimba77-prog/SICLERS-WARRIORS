import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/domain/auth_types.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/blood_repository.dart';

/// Blood donation hub (approved FR-BLD-001..009).
///
/// Patients request blood, verified requests are visible to eligible donors,
/// and donors maintain a privacy-safe profile (BR-005/BR-006). All authority
/// is server-side; this page only renders the surfaces the caller may use.
class BloodDonationPage extends StatelessWidget {
  const BloodDonationPage({
    super.key,
    this.authController,
    this.bloodRepository,
  });

  static const String routeName = '/blood-donation';

  final AuthController? authController;
  final BloodRepository? bloodRepository;

  @override
  Widget build(BuildContext context) {
    final token = (authController ?? SessionScope.controllerOf(context))
        .accessToken;
    if (token == null) {
      return Scaffold(
        appBar: AppBar(title: const Text(AppStrings.bloodRequests)),
        body: const Center(child: Text(AppStrings.notSignedIn)),
      );
    }
    return BloodHomeView(
      accessToken: token,
      repository:
          bloodRepository ?? BloodRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class BloodHomeView extends StatefulWidget {
  const BloodHomeView({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final BloodRepository repository;

  @override
  State<BloodHomeView> createState() => _BloodHomeViewState();
}

class _BloodHomeViewState extends State<BloodHomeView> {
  List<BloodRequest>? _requests;
  BloodDonorProfile? _profile;
  Object? _error;
  bool _loading = true;

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
        widget.repository.listRequests(access: widget.accessToken),
        widget.repository.getDonorProfile(access: widget.accessToken),
      ]);
      if (!mounted) return;
      setState(() {
        _requests = results[0] as List<BloodRequest>;
        _profile = results[1] as BloodDonorProfile?;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.bloodRequests),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: AppStrings.donorProfile,
            onPressed: () => _openDonorProfile(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-blood-request',
        onPressed: () => _openRequestForm(context),
        icon: const Icon(Icons.add),
        label: const Text(AppStrings.requestBlood),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return ErrorRetryView(
        message: AppStrings.bloodLoadFailed,
        onRetry: _load,
      );
    }
    final requests = _requests ?? const <BloodRequest>[];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _DonorSummaryCard(
            profile: _profile,
            onEdit: () => _openDonorProfile(context),
          ),
          if (requests.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: EmptyStateView(
                message: AppStrings.noBloodRequests,
                icon: Icons.bloodtype_outlined,
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                AppStrings.bloodRequests.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            for (final request in requests)
              _BloodRequestCard(
                request: request,
                onTap: () => _openDetail(context, request),
              ),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Future<void> _openRequestForm(BuildContext context) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BloodRequestFormPage(
          accessToken: widget.accessToken,
          repository: widget.repository,
        ),
      ),
    );
    if (created == true && mounted) _load();
  }

  Future<void> _openDetail(
    BuildContext context,
    BloodRequest request,
  ) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => BloodRequestDetailPage(
          accessToken: widget.accessToken,
          repository: widget.repository,
          request: request,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _openDonorProfile(BuildContext context) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DonorProfilePage(
          accessToken: widget.accessToken,
          repository: widget.repository,
          profile: _profile,
        ),
      ),
    );
    if (saved == true && mounted) _load();
  }
}

class _DonorSummaryCard extends StatelessWidget {
  const _DonorSummaryCard({required this.profile, required this.onEdit});

  final BloodDonorProfile? profile;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final profile = this.profile;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: profile == null
            ? Row(
                children: [
                  const Icon(Icons.volunteer_activism_outlined),
                  const SizedBox(width: 12),
                  const Expanded(child: Text(AppStrings.donorProfileHelp)),
                  TextButton(
                    onPressed: onEdit,
                    child: const Text(AppStrings.becomeDonor),
                  ),
                ],
              )
            : Row(
                children: [
                  CircleAvatar(
                    child: Text(
                      profile.bloodGroup,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.donorProfile,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          [
                            if (profile.city.isNotEmpty) profile.city,
                            if (profile.isVerified) AppStrings.donorVerified,
                            '${AppStrings.donationHistory}: ${profile.donationCount}',
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onEdit,
                    child: const Text(AppStrings.editProfile),
                  ),
                ],
              ),
      ),
    );
  }
}

class _BloodRequestCard extends StatelessWidget {
  const _BloodRequestCard({required this.request, required this.onTap});

  final BloodRequest request;
  final VoidCallback onTap;

  Color _statusColor() {
    switch (request.urgency) {
      case 'CRITICAL':
        return AppColors.emergency;
      case 'URGENT':
        return AppColors.secondary;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: _statusColor().withValues(alpha: 0.15),
          child: Text(
            request.bloodGroupNeeded,
            style: TextStyle(
              color: _statusColor(),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          '${request.units} '
          '${request.units == 1 ? 'unit' : 'units'} · ${request.urgency}',
        ),
        subtitle: Text(
          [
            if (request.facilityName.isNotEmpty) request.facilityName,
            if (request.location.isNotEmpty) request.location,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          request.status.replaceAll('_', ' '),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

/// Create a blood request (FR-BLD-005/006, verified before public per BR-005).
class BloodRequestFormPage extends StatefulWidget {
  const BloodRequestFormPage({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final BloodRepository repository;

  @override
  State<BloodRequestFormPage> createState() => _BloodRequestFormPageState();
}

class _BloodRequestFormPageState extends State<BloodRequestFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _locationController = TextEditingController();
  final _facilityController = TextEditingController();

  String _bloodGroup = bloodGroups.first;
  String _urgency = bloodUrgencies.first;
  int _units = 1;
  bool _submitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    _locationController.dispose();
    _facilityController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      await widget.repository.createRequest(
        access: widget.accessToken,
        bloodGroupNeeded: _bloodGroup,
        units: _units,
        urgency: _urgency,
        reason: _reasonController.text.trim(),
        location: _locationController.text.trim(),
        facilityUid: _facilityController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.bloodRequestCreated)),
      );
      Navigator.pop(context, true);
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError(AppStrings.bloodSaveFailed);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.newBloodRequest)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _bloodGroup,
              decoration: const InputDecoration(
                labelText: AppStrings.bloodGroupNeeded,
              ),
              items: [
                for (final group in bloodGroups)
                  DropdownMenuItem(value: group, child: Text(group)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _bloodGroup = value);
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _units,
              decoration: const InputDecoration(
                labelText: AppStrings.unitsNeeded,
              ),
              items: [
                for (var i = 1; i <= 10; i++)
                  DropdownMenuItem(value: i, child: Text('$i')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _units = value);
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _urgency,
              decoration: const InputDecoration(labelText: AppStrings.urgency),
              items: [
                for (final urgency in bloodUrgencies)
                  DropdownMenuItem(value: urgency, child: Text(urgency)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _urgency = value);
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: AppStrings.reasonForRequest,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: AppStrings.requestLocation,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _facilityController,
              decoration: const InputDecoration(
                labelText: AppStrings.facilityUidHint,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(
                _submitting ? AppStrings.saving : AppStrings.requestBlood,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Request detail with matches and donor response actions (FR-BLD-008/009).
class BloodRequestDetailPage extends StatefulWidget {
  const BloodRequestDetailPage({
    super.key,
    required this.accessToken,
    required this.repository,
    required this.request,
  });

  final String accessToken;
  final BloodRepository repository;
  final BloodRequest request;

  @override
  State<BloodRequestDetailPage> createState() => _BloodRequestDetailPageState();
}

class _BloodRequestDetailPageState extends State<BloodRequestDetailPage> {
  late BloodRequest _request = widget.request;
  List<BloodMatch>? _matches;
  Object? _error;
  bool _loading = true;
  int? _respondingMatchId;

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  Future<void> _loadMatches() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final matches = await widget.repository.listMatches(
        access: widget.accessToken,
        requestUid: _request.uid,
      );
      if (!mounted) return;
      setState(() {
        _matches = matches;
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

  Future<void> _respond(BloodMatch match, bool accept) async {
    setState(() => _respondingMatchId = match.id);
    try {
      await widget.repository.respondToMatch(
        access: widget.accessToken,
        matchId: match.id,
        accept: accept,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.matchResponded)),
      );
      await _loadMatches();
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError(AppStrings.matchRespondFailed);
    } finally {
      if (mounted) setState(() => _respondingMatchId = null);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.cancelRequest),
        content: const Text(AppStrings.cancelRequestConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(AppStrings.cancelRequest),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final updated = await widget.repository.cancelRequest(
        access: widget.accessToken,
        uid: _request.uid,
      );
      if (!mounted) return;
      setState(() => _request = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.requestCancelled)),
      );
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError(AppStrings.bloodSaveFailed);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.bloodRequests)),
      body: RefreshIndicator(
        onRefresh: _loadMatches,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _DetailCard(request: _request),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppStrings.matches.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: AppStrings.retry,
                  onPressed: _loadMatches,
                ),
              ],
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: LoadingView(),
              )
            else if (_error != null)
              ErrorRetryView(
                message: AppStrings.bloodLoadFailed,
                onRetry: _loadMatches,
              )
            else if ((_matches ?? const []).isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: EmptyStateView(
                  message: AppStrings.noMatches,
                  icon: Icons.search_off,
                ),
              )
            else
              for (final match in _matches!)
                _MatchCard(
                  match: match,
                  busy: _respondingMatchId == match.id,
                  onAccept: () => _respond(match, true),
                  onDecline: () => _respond(match, false),
                ),
            if (_request.isOpen) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _cancel,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text(AppStrings.cancelRequest),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.request});

  final BloodRequest request;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text(request.bloodGroupNeeded)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${request.units} '
                    '${request.units == 1 ? 'unit' : 'units'} · '
                    '${request.urgency}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text(request.status.replaceAll('_', ' '))),
              ],
            ),
            const Divider(height: 24),
            if (request.facilityName.isNotEmpty)
              _DetailRow(
                icon: Icons.local_hospital_outlined,
                label: request.facilityName,
              ),
            if (request.location.isNotEmpty)
              _DetailRow(
                icon: Icons.place_outlined,
                label: request.location,
              ),
            if (request.reason.isNotEmpty)
              _DetailRow(
                icon: Icons.notes_outlined,
                label: request.reason,
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final BloodMatch match;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text(match.donor.bloodGroup)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          if (match.donor.city.isNotEmpty) match.donor.city,
                          if (match.donor.region.isNotEmpty) match.donor.region,
                        ].join(' · '),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        '${AppStrings.matchScore}: '
                        '${match.matchScore.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Chip(label: Text(match.status)),
              ],
            ),
            if (match.matchReason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  match.matchReason,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (match.awaitingResponse)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: busy ? null : onDecline,
                    child: const Text(AppStrings.decline),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: busy ? null : onAccept,
                    child: const Text(AppStrings.accept),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Donor self profile (blood_donors.self_manage, BR-006 privacy safe).
class DonorProfilePage extends StatefulWidget {
  const DonorProfilePage({
    super.key,
    required this.accessToken,
    required this.repository,
    this.profile,
  });

  final String accessToken;
  final BloodRepository repository;
  final BloodDonorProfile? profile;

  @override
  State<DonorProfilePage> createState() => _DonorProfilePageState();
}

class _DonorProfilePageState extends State<DonorProfilePage> {
  final _regionController = TextEditingController();
  final _cityController = TextEditingController();

  String _bloodGroup = bloodGroups.first;
  bool _isAvailable = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    if (profile != null) {
      if (bloodGroups.contains(profile.bloodGroup)) {
        _bloodGroup = profile.bloodGroup;
      }
      _regionController.text = profile.region;
      _cityController.text = profile.city;
      _isAvailable = profile.isAvailable;
    }
  }

  @override
  void dispose() {
    _regionController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repository.saveDonorProfile(
        access: widget.accessToken,
        bloodGroup: _bloodGroup,
        region: _regionController.text.trim(),
        city: _cityController.text.trim(),
        isAvailable: _isAvailable,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.donorSaved)),
      );
      Navigator.pop(context, true);
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError(AppStrings.donorSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.donorProfile)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            AppStrings.donorProfileHelp,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _bloodGroup,
            decoration: const InputDecoration(labelText: AppStrings.bloodGroup),
            items: [
              for (final group in bloodGroups)
                DropdownMenuItem(value: group, child: Text(group)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _bloodGroup = value);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _regionController,
            decoration: const InputDecoration(labelText: AppStrings.region),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _cityController,
            decoration: const InputDecoration(labelText: AppStrings.city),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(AppStrings.availableToDonate),
            value: _isAvailable,
            onChanged: (value) => setState(() => _isAvailable = value),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? AppStrings.saving : AppStrings.save),
          ),
        ],
      ),
    );
  }
}
