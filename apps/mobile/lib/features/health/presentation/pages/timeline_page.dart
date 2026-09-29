import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/health_repository.dart';

/// Chronological health timeline (doses, medications, symptoms, updates).
class TimelinePage extends StatelessWidget {
  const TimelinePage({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  static const String routeName = '/health/timeline';

  final String accessToken;
  final HealthRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.timeline)),
      body: SafeArea(
        child: _TimelineView(accessToken: accessToken, repository: repository),
      ),
    );
  }
}

class _TimelineView extends StatefulWidget {
  const _TimelineView({
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final HealthRepository repository;

  @override
  State<_TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<_TimelineView> {
  List<TimelineEntry> _entries = [];
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
      final entries = await widget.repository.fetchTimeline(
        access: widget.accessToken,
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(AppStrings.timelineLoadFailed),
            ),
            OutlinedButton(
              onPressed: _load,
              child: const Text(AppStrings.retry),
            ),
          ],
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(child: Text(AppStrings.noTimelineEdits));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _entries.length,
        itemBuilder: (context, index) {
          final e = _entries[index];
          return Card(
            child: ListTile(
              leading: Icon(
                _iconFor(e.eventType),
                color: _colorFor(e.eventType),
              ),
              title: Text(e.summary),
              subtitle: Text(_humanTime(e.occurredAt) +
                  (_labelFor(e.eventType).isEmpty
                      ? ''
                      : ' · ${_labelFor(e.eventType)}')),
              isThreeLine: false,
            ),
          );
        },
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'MEDICATION_CREATED':
        return Icons.medication_outlined;
      case 'MEDICATION_UPDATED':
      case 'MEDICATION_DEACTIVATED':
        return Icons.medication_liquid;
      case 'DOSE_LOGGED':
        return Icons.check_circle_outline;
      case 'DOSE_SKIPPED':
      case 'DOSE_SNOOZED':
        return Icons.snooze_outlined;
      case 'SYMPTOM_RECORDED':
        return Icons.health_and_safety_outlined;
      case 'PROFILE_UPDATED':
        return Icons.person_outline;
      default:
        return Icons.bolt_outlined;
    }
  }

  Color _colorFor(String type) {
    if (type == 'DOSE_LOGGED') return AppColors.success;
    if (type == 'SYMPTOM_RECORDED') return AppColors.primary;
    if (type.contains('DEACTIVATED')) return AppColors.emergency;
    return AppColors.textSecondary;
  }

  String _labelFor(String type) {
    switch (type) {
      case 'MEDICATION_CREATED':
        return AppStrings.medications;
      case 'MEDICATION_DEACTIVATED':
        return AppStrings.stopped;
      case 'DOSE_LOGGED':
        return AppStrings.doseTaken;
      case 'DOSE_SKIPPED':
        return AppStrings.doseSkipped;
      case 'DOSE_SNOOZED':
        return AppStrings.doseSnoozed;
      case 'SYMPTOM_RECORDED':
        return AppStrings.symptoms;
      case 'PROFILE_UPDATED':
        return AppStrings.profile;
      default:
        return '';
    }
  }

  String _humanTime(String? iso) {
    final dt = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}