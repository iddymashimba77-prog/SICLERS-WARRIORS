import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/domain/auth_types.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../../profile/data/profile_repository.dart';
import '../../data/emergency_repository.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../shared/widgets/signed_out_gate.dart';

/// Emergency quick-request flow (approved FR-EMG-001..006, screens EMG-001..006).
///
/// Red is reserved for emergency surfaces. The SOS action arms on a
/// press-and-hold (EMG-002), then a confirmation sheet collects/edits the
/// request (EMG-003) before the rate-limited, idempotent POST. Tracking
/// (EMG-004) polls the request, resolution (EMG-005) clears the red state, and
/// access grants (EMG-006) are shown to the patient. When the network fails the
/// alert is never queued or reported as sent — the user is told to call
/// emergency services directly.
class EmergencyPage extends StatelessWidget {
  const EmergencyPage({
    super.key,
    this.authController,
    this.emergencyRepository,
    this.profileRepository,
  });

  static const String routeName = '/emergency';

  final AuthController? authController;
  final EmergencyRepository? emergencyRepository;
  final ProfileRepository? profileRepository;

  @override
  Widget build(BuildContext context) {
    final token = (authController ?? SessionScope.controllerOf(context))
        .accessToken;
    if (token == null) {
      return const SignedOutGate();
    }
    return EmergencyHomeView(
      accessToken: token,
      repository: emergencyRepository ??
          EmergencyRepository(tokenStore: EphemeralTokenStore()),
      profileRepository: profileRepository,
    );
  }
}

class EmergencyHomeView extends StatefulWidget {
  const EmergencyHomeView({
    super.key,
    required this.accessToken,
    required this.repository,
    this.profileRepository,
  });

  final String accessToken;
  final EmergencyRepository repository;
  final ProfileRepository? profileRepository;

  @override
  State<EmergencyHomeView> createState() => _EmergencyHomeViewState();
}

class _EmergencyHomeViewState extends State<EmergencyHomeView> {
  final _descriptionController = TextEditingController();
  late final ProfileRepository _profile = widget.profileRepository ??
      ProfileRepository(tokenStore: EphemeralTokenStore());

  List<EmergencyRequest>? _requests;
  List<EmergencyAccessGrant> _grants = const [];
  PatientProfile? _contact;
  Object? _error;
  bool _loading = true;
  bool _submitting = false;
  bool _busy = false;

  String _type = emergencyTypes.first;
  String _severity = emergencySeverities.first;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    List<EmergencyRequest> requests = const [];
    List<EmergencyAccessGrant> grants = const [];
    PatientProfile? contact;
    Object? error;
    try {
      requests = await widget.repository.listRequests(access: widget.accessToken);
    } catch (e) {
      error = e;
    }
    try {
      grants = await widget.repository.listAccessGrants(access: widget.accessToken);
    } catch (_) {
      grants = const [];
    }
    try {
      contact = await _profile.fetch(access: widget.accessToken);
    } catch (_) {
      contact = null;
    }
    if (!mounted) return;
    setState(() {
      _requests = requests;
      _grants = grants;
      _contact = contact;
      _error = error;
      _loading = false;
    });
  }

  Future<void> _submit(EmergencyDraft draft) async {
    setState(() => _submitting = true);
    try {
      final created = await widget.repository.createRequest(
        access: widget.accessToken,
        type: draft.type,
        severity: draft.severity,
        description: draft.description,
        location: draft.location,
      );
      if (!mounted) return;
      _descriptionController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.emergencyCreated)),
      );
      await _load();
      if (mounted) await _openTracking(created);
    } on AuthException catch (e) {
      _showNotSent(
        e.statusCode == 429 ? AppStrings.sosRateLimited : AppStrings.sosNotSentCallNow,
      );
    } catch (_) {
      _showNotSent(AppStrings.sosNotSentCallNow);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmAndSubmit() async {
    final draft = await showModalBottomSheet<EmergencyDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EmergencyConfirmSheet(
        prefill: _contact,
        defaultType: _type,
        defaultSeverity: _severity,
        defaultDescription: _descriptionController.text.trim(),
      ),
    );
    if (draft != null) await _submit(draft);
  }

  Future<void> _submitInlineForm() async {
    await _submit(
      EmergencyDraft(
        type: _type,
        severity: _severity,
        description: _descriptionController.text.trim(),
        shareConsent: true,
      ),
    );
  }

  /// Network failure must never look like a sent alert (safety + integrity).
  void _showNotSent(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: AppColors.emergency),
        title: const Text(AppStrings.sosCallInstruction),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text(AppStrings.close),
          ),
        ],
      ),
    );
  }

  Future<void> _openTracking(EmergencyRequest request) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EmergencyTrackingSheet(
        accessToken: widget.accessToken,
        repository: widget.repository,
        initial: request,
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _run(Future<EmergencyRequest> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.emergencyUpdated)),
      );
      await _load();
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError(AppStrings.emergencyActionFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.emergencyHome),
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
            _SosHoldButton(
              enabled: !_submitting,
              onTriggered: _confirmAndSubmit,
            ),
            const SizedBox(height: 12),
            const _EmergencyNumbersCard(),
            if (_contact?.emergencyContactName != null &&
                _contact!.emergencyContactName!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _EmergencyContactLine(contact: _contact!),
            ],
            const SizedBox(height: 16),
            Text(
              AppStrings.activeEmergencies.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: LoadingView(),
              )
            else if (_error != null)
              ErrorRetryView(
                message: AppStrings.emergencyLoadFailed,
                onRetry: _load,
              )
            else if ((_requests ?? const []).isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: EmptyStateView(
                  message: AppStrings.noEmergencies,
                  icon: Icons.sos_outlined,
                ),
              )
            else
              for (final emergency in _requests!)
                _EmergencyCard(
                  emergency: emergency,
                  busy: !_busy,
                  onOpen: () => _openTracking(emergency),
                  onValidate: () => _run(
                    () => widget.repository.validate(
                      access: widget.accessToken,
                      uid: emergency.uid,
                    ),
                  ),
                  onRespond: () => _run(
                    () => widget.repository.respond(
                      access: widget.accessToken,
                      uid: emergency.uid,
                    ),
                  ),
                  onEscalate: () => _run(
                    () => widget.repository.escalate(
                      access: widget.accessToken,
                      uid: emergency.uid,
                    ),
                  ),
                  onResolve: () => _run(
                    () => widget.repository.resolve(
                      access: widget.accessToken,
                      uid: emergency.uid,
                    ),
                  ),
                  onCancel: () => _run(
                    () => widget.repository.cancel(
                      access: widget.accessToken,
                      uid: emergency.uid,
                    ),
                  ),
                ),
            const SizedBox(height: 16),
            _EmergencyTriggerCard(
              type: _type,
              severity: _severity,
              controller: _descriptionController,
              submitting: _submitting,
              onTypeChanged: (v) => setState(() => _type = v),
              onSeverityChanged: (v) => setState(() => _severity = v),
              onSubmit: _submitInlineForm,
            ),
            const SizedBox(height: 16),
            _AccessGrantsCard(grants: _grants),
          ],
        ),
      ),
    );
  }
}

/// EMG-002: the red SOS action must be deliberately armed (press-and-hold).
/// Tanzania emergency lines that must always be reachable, even with no data
/// connection — the SOS request path needs the network, a phone call does not.
///
/// 115 — M-MAMA / AMBULANCE (free, maternal & emergency ambulance line, the
///       number sickle-cell warriors in Tanzania are told to call for a
///       transfer to a recognised facility).
/// 112 — national emergency number (police, fire, ambulance dispatch).
///
/// Both launch the platform dialler through `tel:`; the page never claims a
/// call happened, because the app cannot know that.
class _EmergencyNumbersCard extends StatelessWidget {
  const _EmergencyNumbersCard();

  static const List<({String number, String labelKey, String label, IconData icon})>
      _lines = [
    (
      number: '115',
      labelKey: 'sos.mMama',
      label: 'M-MAMA ambulance & maternal emergency',
      icon: Icons.local_hospital_outlined,
    ),
    (
      number: '112',
      labelKey: 'sos.nationalEmergency',
      label: 'National emergency number',
      icon: Icons.emergency_outlined,
    ),
  ];

  Future<void> _dial(BuildContext context, String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n(context).tr('sos.cannotDial')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.phone_in_talk_outlined,
                    size: 18, color: AppColors.emergency),
                const SizedBox(width: 8),
                Text(
                  l10n(context).tr('sos.callNow'),
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n(context).tr('sos.callNowHint'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final line in _lines)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(line.icon, color: AppColors.emergency),
                title: Text(
                  line.number,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.emergency,
                  ),
                ),
                subtitle: Text(l10n(context).tr(line.labelKey, args: {
                  'service': line.label,
                })),
                trailing: const Icon(Icons.call),
                onTap: () => _dial(context, line.number),
              ),
          ],
        ),
      ),
    );
  }
}

class _SosHoldButton extends StatefulWidget {
  const _SosHoldButton({required this.onTriggered, required this.enabled});

  final VoidCallback onTriggered;
  final bool enabled;

  @override
  State<_SosHoldButton> createState() => _SosHoldButtonState();
}

class _SosHoldButtonState extends State<_SosHoldButton> {
  static const _armDuration = Duration(milliseconds: 600);
  Timer? _timer;
  bool _holding = false;

  void _start() {
    if (!widget.enabled) return;
    setState(() => _holding = true);
    _timer = Timer(_armDuration, widget.onTriggered);
  }

  void _cancel() {
    _timer?.cancel();
    if (mounted) setState(() => _holding = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: AppStrings.sos,
      child: GestureDetector(
        key: const ValueKey('sos_hold'),
        onTapDown: (_) => _start(),
        onTapUp: (_) => _cancel(),
        onTapCancel: _cancel,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 96,
          decoration: BoxDecoration(
            color: AppColors.emergency.withValues(alpha: _holding ? 1 : 0.9),
            borderRadius: AppShapes.card,
            boxShadow: _holding
                ? [
                    BoxShadow(
                      color: AppColors.emergency.withValues(alpha: 0.5),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sos, color: AppColors.onPrimary, size: 32),
                const SizedBox(height: 4),
                Text(
                  _holding ? AppStrings.sosArmed : AppStrings.sosHoldToArm,
                  style: const TextStyle(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmergencyContactLine extends StatelessWidget {
  const _EmergencyContactLine({required this.contact});

  final PatientProfile contact;

  @override
  Widget build(BuildContext context) {
    final detail = [
      contact.emergencyContactName,
      if (contact.emergencyContactRelation != null &&
          contact.emergencyContactRelation!.isNotEmpty)
        '(${contact.emergencyContactRelation})',
      if (contact.emergencyContactPhone != null &&
          contact.emergencyContactPhone!.isNotEmpty)
        contact.emergencyContactPhone,
    ].whereType<String>().join(' ');
    return Row(
      children: [
        const Icon(Icons.contact_phone_outlined, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${AppStrings.emergencyPrefill}: $detail',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// Editable request payload captured by the confirmation sheet (EMG-003).
class EmergencyDraft {
  const EmergencyDraft({
    required this.type,
    required this.severity,
    required this.description,
    required this.shareConsent,
    this.location,
  });

  final String type;
  final String severity;
  final String description;
  final bool shareConsent;
  final Map<String, dynamic>? location;
}

/// EMG-002 + EMG-003 confirmation sheet: EMS disclaimer, editable fields and an
/// explicit consent gate before an alert can be raised.
class EmergencyConfirmSheet extends StatefulWidget {
  const EmergencyConfirmSheet({
    super.key,
    this.prefill,
    required this.defaultType,
    required this.defaultSeverity,
    this.defaultDescription = '',
  });

  final PatientProfile? prefill;
  final String defaultType;
  final String defaultSeverity;
  final String defaultDescription;

  @override
  State<EmergencyConfirmSheet> createState() => _EmergencyConfirmSheetState();
}

class _EmergencyConfirmSheetState extends State<EmergencyConfirmSheet> {
  late String _type = widget.defaultType;
  late String _severity = widget.defaultSeverity;
  late final TextEditingController _description =
      TextEditingController(text: widget.defaultDescription);
  final _location = TextEditingController();
  bool _consent = false;

  @override
  void dispose() {
    _description.dispose();
    _location.dispose();
    super.dispose();
  }

  void _submit() {
    final locationText = _location.text.trim();
    Navigator.of(context).pop(
      EmergencyDraft(
        type: _type,
        severity: _severity,
        description: _description.text.trim(),
        shareConsent: _consent,
        location: locationText.isEmpty ? null : {'text': locationText},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contact = widget.prefill;
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
            Row(
              children: [
                const Icon(Icons.sos, color: AppColors.emergency),
                const SizedBox(width: 8),
                Text(
                  AppStrings.sosConfirmTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(AppStrings.sosConfirmBody),
            const SizedBox(height: 8),
            Text(
              AppStrings.sosCallInstruction,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (contact?.emergencyContactName != null) ...[
              const SizedBox(height: 12),
              _EmergencyContactLine(contact: contact!),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: AppStrings.emergencyType),
              items: [
                for (final t in emergencyTypes)
                  DropdownMenuItem(value: t, child: Text(t.replaceAll('_', ' '))),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _type = v);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _severity,
              decoration:
                  const InputDecoration(labelText: AppStrings.emergencySeverity),
              items: [
                for (final s in emergencySeverities)
                  DropdownMenuItem(value: s, child: Text(s)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _severity = v);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration:
                  const InputDecoration(labelText: AppStrings.describeEmergency),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _location,
              decoration: const InputDecoration(
                labelText: AppStrings.sosLocationLabel,
              ),
            ),
            CheckboxListTile(
              value: _consent,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setState(() => _consent = v ?? false),
              title: const Text(AppStrings.sosShareConsent),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.emergency,
                  foregroundColor: AppColors.onPrimary,
                ),
                onPressed: _consent ? _submit : null,
                icon: const Icon(Icons.send),
                label: const Text(AppStrings.submitEmergency),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// EMG-004/EMG-005 tracking sheet: polls status, shows the responder timeline
/// and offers cancel; resolves into a success state with no residual red.
class EmergencyTrackingSheet extends StatefulWidget {
  const EmergencyTrackingSheet({
    super.key,
    required this.accessToken,
    required this.repository,
    required this.initial,
  });

  final String accessToken;
  final EmergencyRepository repository;
  final EmergencyRequest initial;

  @override
  State<EmergencyTrackingSheet> createState() => _EmergencyTrackingSheetState();
}

class _EmergencyTrackingSheetState extends State<EmergencyTrackingSheet> {
  static const _pollInterval = Duration(seconds: 5);
  static const _lifecycle = [
    'CREATED',
    'VALIDATING',
    'ACTIVE',
    'RESPONDING',
    'ESCALATED',
    'RESOLVED',
  ];

  late EmergencyRequest _request = widget.initial;
  Timer? _poll;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (_request.isActive) {
      _poll = Timer.periodic(_pollInterval, (_) => _refresh());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final updated = await widget.repository.getRequest(
        access: widget.accessToken,
        uid: _request.uid,
      );
      if (!mounted) return;
      setState(() => _request = updated);
      if (!_request.isActive) _poll?.cancel();
    } catch (_) {
      // Polling failures are non-fatal; keep the last known state.
    }
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      await widget.repository.cancel(
        access: widget.accessToken,
        uid: _request.uid,
      );
      await _refresh();
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _request.isResolved;
    final cancelled = _request.status == 'CANCELLED';
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
                  Icon(
                    resolved ? Icons.check_circle : Icons.sos,
                    color: resolved
                        ? AppColors.success
                        : cancelled
                            ? AppColors.textSecondary
                            : AppColors.emergency,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      resolved
                          ? AppStrings.trackingResolvedTitle
                          : AppStrings.trackingTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (resolved) ...[
                Text(AppStrings.trackingResolvedBody),
                const SizedBox(height: 12),
              ],
              LinearProgressIndicator(
                value: _progressValue(),
                backgroundColor: AppColors.emergency.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation(
                  resolved ? AppColors.success : AppColors.emergency,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                AppStrings.trackingTimeline.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 4),
              for (final step in _timelineSteps())
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: step.reached,
                  onChanged: null,
                  title: Text(step.label.replaceAll('_', ' ')),
                ),
              if (_request.locationLabel.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  AppStrings.trackingLocation.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(_request.locationLabel),
              ],
              const SizedBox(height: 12),
              Text(
                AppStrings.trackingResponders.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              if (_request.responders.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(AppStrings.trackingNoResponders),
                )
              else
                for (final responder in _request.responders)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: Text(responder.role.replaceAll('_', ' ')),
                    subtitle: Text(responder.status.replaceAll('_', ' ')),
                  ),
              if (_request.isActive) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _cancel,
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text(AppStrings.cancelRequest),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  double _progressValue() {
    if (_request.status == 'CANCELLED' || _request.status == 'EXPIRED') return 0;
    final index = _lifecycle.indexOf(_request.status);
    if (index < 0) return 0;
    return (index + 1) / _lifecycle.length;
  }

  List<_TimelineStep> _timelineSteps() {
    if (_request.status == 'CANCELLED' || _request.status == 'EXPIRED') {
      return [
        const _TimelineStep('CREATED', reached: true),
        _TimelineStep(_request.status, reached: true),
      ];
    }
    final current = _lifecycle.indexOf(_request.status);
    return [
      for (var i = 0; i < _lifecycle.length; i++)
        _TimelineStep(_lifecycle[i], reached: i <= current),
    ];
  }
}

class _TimelineStep {
  const _TimelineStep(this.label, {required this.reached});

  final String label;
  final bool reached;
}

/// EMG-006: patient-visible, time-bounded professional access grants.
class _AccessGrantsCard extends StatelessWidget {
  const _AccessGrantsCard({required this.grants});

  final List<EmergencyAccessGrant> grants;

  @override
  Widget build(BuildContext context) {
    final active = grants.where((g) => g.isActive).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.accessStatus.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 8),
            if (active.isEmpty)
              const Text(AppStrings.accessNone)
            else
              for (final grant in active)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${AppStrings.accessGrantedUntil} '
                    '${grant.expiresAt ?? '—'}',
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _EmergencyTriggerCard extends StatelessWidget {
  const _EmergencyTriggerCard({
    required this.type,
    required this.severity,
    required this.controller,
    required this.submitting,
    required this.onTypeChanged,
    required this.onSeverityChanged,
    required this.onSubmit,
  });

  final String type;
  final String severity;
  final TextEditingController controller;
  final bool submitting;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onSeverityChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.emergency.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.emergency.withValues(alpha: 0.4)),
        borderRadius: AppShapes.tile,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sos, color: AppColors.emergency),
                const SizedBox(width: 8),
                Text(
                  AppStrings.triggerEmergency,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration:
                  const InputDecoration(labelText: AppStrings.emergencyType),
              items: [
                for (final t in emergencyTypes)
                  DropdownMenuItem(value: t, child: Text(t.replaceAll('_', ' '))),
              ],
              onChanged: (v) {
                if (v != null) onTypeChanged(v);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: severity,
              decoration:
                  const InputDecoration(labelText: AppStrings.emergencySeverity),
              items: [
                for (final s in emergencySeverities)
                  DropdownMenuItem(value: s, child: Text(s)),
              ],
              onChanged: (v) {
                if (v != null) onSeverityChanged(v);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: AppStrings.describeEmergency,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.emergency,
                  foregroundColor: AppColors.onPrimary,
                ),
                onPressed: submitting ? null : onSubmit,
                icon: const Icon(Icons.send),
                label: Text(
                  submitting
                      ? AppStrings.saving
                      : AppStrings.submitEmergency,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.emergencyCallNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard({
    required this.emergency,
    required this.busy,
    required this.onOpen,
    required this.onValidate,
    required this.onRespond,
    required this.onEscalate,
    required this.onResolve,
    required this.onCancel,
  });

  final EmergencyRequest emergency;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onValidate;
  final VoidCallback onRespond;
  final VoidCallback onEscalate;
  final VoidCallback onResolve;
  final VoidCallback onCancel;

  Color _severityColor() {
    switch (emergency.severity) {
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
                  CircleAvatar(
                    backgroundColor: _severityColor().withValues(alpha: 0.15),
                    child: Icon(
                      Icons.sos,
                      color: _severityColor(),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${emergency.type.replaceAll('_', ' ')} · '
                          '${emergency.severity}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          emergency.description.isEmpty
                              ? emergency.status.replaceAll('_', ' ')
                              : emergency.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Chip(label: Text(emergency.status.replaceAll('_', ' '))),
                ],
              ),
              if (emergency.isActive)
                Align(
                  alignment: Alignment.centerRight,
                  child: PopupMenuButton<String>(
                    enabled: busy,
                    onSelected: (value) {
                      switch (value) {
                        case 'validate':
                          onValidate();
                        case 'respond':
                          onRespond();
                        case 'escalate':
                          onEscalate();
                        case 'resolve':
                          onResolve();
                        case 'cancel':
                          onCancel();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'validate',
                        child: Text(AppStrings.validateEmergency),
                      ),
                      PopupMenuItem(
                        value: 'respond',
                        child: Text(AppStrings.respondEmergency),
                      ),
                      PopupMenuItem(
                        value: 'escalate',
                        child: Text(AppStrings.escalateEmergency),
                      ),
                      PopupMenuItem(
                        value: 'resolve',
                        child: Text(AppStrings.resolveEmergency),
                      ),
                      PopupMenuItem(
                        value: 'cancel',
                        child: Text(AppStrings.cancelEmergency),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
