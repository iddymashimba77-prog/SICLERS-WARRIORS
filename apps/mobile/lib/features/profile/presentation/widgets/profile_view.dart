import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../data/profile_repository.dart';
import 'patient_profile_form.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({
    super.key,
    required this.repository,
    required this.accessToken,
    this.canEdit = true,
  });

  final ProfileRepository repository;
  final String accessToken;
  final bool canEdit;

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  PatientProfile? _profile;
  Object? _error;
  bool _loading = true;
  bool _editing = false;

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
      final profile = await widget.repository.fetch(access: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _profile = profile;
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

  Future<void> _save(PatientProfile updated) async {
    final saved =
        await widget.repository.update(access: widget.accessToken, profile: updated);
    if (!mounted) return;
    setState(() {
      _profile = saved;
      _editing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              const Text(AppStrings.profileLoadFailed),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final profile = _profile;
    if (profile == null) {
      return const SizedBox.shrink();
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (widget.canEdit)
                TextButton.icon(
                  onPressed: () => setState(() => _editing = !_editing),
                  icon: Icon(_editing ? Icons.close : Icons.edit_outlined),
                  label: Text(
                    _editing ? AppStrings.cancel : AppStrings.editProfile,
                  ),
                ),
            ],
          ),
          if (_editing)
            PatientProfileForm(
              initial: profile,
              onSubmit: _save,
              onCancel: () => setState(() => _editing = false),
              facilityLoader: widget.repository.fetchFacilities,
            )
          else
            PatientProfileForm(
              initial: profile,
              onSubmit: _save,
              readOnly: true,
            ),
        ],
      ),
    );
  }
}