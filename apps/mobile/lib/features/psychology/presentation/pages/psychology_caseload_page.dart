import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../shared/widgets/signed_out_gate.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/domain/auth_types.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../../education/presentation/pages/education_page.dart';
import '../../data/psychology_repository.dart';

/// Caseload for the psychologist (§2): consented patients ∪ booked
/// appointments, identity rows only — records stay behind the other tabs
/// where the server re-checks consent per request.
class PsychologyCaseloadPage extends StatelessWidget {
  const PsychologyCaseloadPage({super.key, this.authController, this.repository});

  final AuthController? authController;
  final PsychologyRepository? repository;

  @override
  Widget build(BuildContext context) {
    final token =
        (authController ?? SessionScope.controllerOf(context)).accessToken;
    if (token == null) return const SignedOutGate();
    return _CaseloadView(
      accessToken: token,
      repository: repository ??
          PsychologyRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class _CaseloadView extends StatefulWidget {
  const _CaseloadView({required this.accessToken, required this.repository});

  final String accessToken;
  final PsychologyRepository repository;

  @override
  State<_CaseloadView> createState() => _CaseloadViewState();
}

class _CaseloadViewState extends State<_CaseloadView> {
  List<PsychologyCaseloadEntry> _items = const [];
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
      final items = await widget.repository.caseload(access: widget.accessToken);
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
    if (error is AuthException) {
      final message = error.message.trim();
      if (message.isNotEmpty && !message.contains('Exception')) return message;
    }
    return AppStrings.psychLoadFailed;
  }

  String _when(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    return dt == null ? '' : dt.toLocal().toString().split('.').first;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.psychCaseload),
        actions: [
          IconButton(
            tooltip: AppStrings.psychEducationTitle,
            onPressed: () =>
                Navigator.of(context).pushNamed(EducationPage.routeName),
            icon: const Icon(Icons.menu_book_outlined),
          ),
          IconButton(
            tooltip: s.tr('common.refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(s),
    );
  }

  Widget _buildBody(AppLocalizations s) {
    if (_loading) return LoadingView(label: s.tr('common.loading'));
    if (_error != null) {
      return ErrorRetryView(message: _messageFor(_error!), onRetry: _load);
    }
    if (_items.isEmpty) {
      return EmptyStateView(message: AppStrings.psychCaseloadEmpty);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final entry = _items[index];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Icon(
                  entry.hasConsent
                      ? Icons.psychology_outlined
                      : Icons.psychology,
                ),
              ),
              title: Text(entry.patientName),
              subtitle: (entry.nextAppointmentAt == null &&
                      entry.lastAppointmentAt == null)
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (entry.nextAppointmentAt != null)
                          Text(
                            '${AppStrings.psychNextSession}: ${_when(entry.nextAppointmentAt)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if (entry.lastAppointmentAt != null)
                          Text(
                            _when(entry.lastAppointmentAt),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
              trailing: Chip(
                label: Text(
                  entry.hasConsent
                      ? AppStrings.psychConsentGranted
                      : AppStrings.psychNoConsent,
                  style: const TextStyle(fontSize: 11),
                ),
                visualDensity: VisualDensity.compact,
              ),
              isThreeLine: true,
            ),
          );
        },
      ),
    );
  }
}
