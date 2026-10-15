import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../public/presentation/pages/public_home_page.dart';
import '../../data/auth_repository.dart';
import '../controllers/auth_controller.dart';
import '../widgets/session_scope.dart';
import 'doctor_verification_page.dart';
import 'organization_verification_page.dart';

/// C5 — verification-document submission surface.
///
/// Shown right after sign-up to professional (DOCTOR / PSYCHOLOGIST /
/// SOCIAL_SUPPORT) and facility (HOSPITAL / CLINIC / ORGANIZATION) accounts,
/// and reachable again from the status screens. Applicants attach the
/// government-verified documents the server mandates, upload them through
/// the certificate pipeline and submit the bundle for the officer review queue.
class VerificationSubmissionPage extends StatefulWidget {
  const VerificationSubmissionPage({super.key, this.controller, this.roleCode});

  static const String routeName = '/verify-documents';

  final AuthController? controller;

  /// Optional override from the sign-up flow ('' → derive from session roles).
  final String? roleCode;

  @override
  State<VerificationSubmissionPage> createState() =>
      _VerificationSubmissionPageState();
}

class _VerificationSubmissionPageState extends State<VerificationSubmissionPage> {
  final _nameController = TextEditingController();
  String? _facilityType;
  final _cityController = TextEditingController();
  final _regNoController = TextEditingController();
  final Map<String, PlatformFile> _picked = {};
  final List<String> _extraDocTypes = [];
  bool _submitting = false;

  AuthController get _controller =>
      widget.controller ?? SessionScope.controllerOf(context);

  bool get _isFacility =>
      {'HOSPITAL', 'CLINIC', 'ORGANIZATION'}.contains(_effectiveRole);

  String get _effectiveRole {
    final explicit = widget.roleCode;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final roles = _controller.roles;
    for (final r in ['DOCTOR', 'PSYCHOLOGIST', 'SOCIAL_SUPPORT']) {
      if (roles.contains(r)) return r;
    }
    for (final r in ['HOSPITAL', 'CLINIC', 'ORGANIZATION']) {
      if (roles.contains(r)) return r;
    }
    return 'DOCTOR';
  }

  String _roleTypeLabel(String code) {
    switch (code) {
      case 'HOSPITAL':
        return 'auth.roleHospital';
      case 'CLINIC':
        return 'auth.roleClinic';
      default:
        return 'auth.roleOrganization';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _regNoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isFacility = _isFacility;
    final mandatory = <_DocSlot>[
      _DocSlot(
        docType: isFacility ? 'FACILITY_REGISTRATION' : 'CERTIFICATE',
        label: s.tr(isFacility
            ? 'verify.facilityDocLabel'
            : 'verify.certificateLabel'),
        hint: isFacility ? null : s.tr('verify.certificateHint'),
      ),
      _DocSlot(
        docType: 'NATIONAL_ID',
        label: s.tr('verify.nidaLabel'),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(s.tr('auth.verificationUpload'))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.badge_outlined,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  s.tr('auth.verificationHint'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                if (isFacility) ...[
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: s.tr('verify.facilityName'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _facilityType,
                    decoration: InputDecoration(
                      labelText: s.tr('verify.facilityType'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final c in ['HOSPITAL', 'CLINIC', 'ORGANIZATION'])
                        DropdownMenuItem(
                          value: c,
                          child: Text(s.tr(_roleTypeLabel(c))),
                        ),
                    ],
                    onChanged: (v) => setState(() => _facilityType = v),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cityController,
                    decoration: InputDecoration(
                      labelText: s.tr('verify.facilityRegion'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _regNoController,
                    decoration: InputDecoration(
                      labelText: s.tr('verify.registrationNumber'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                Text(
                  s.tr('auth.verificationDocsNote'),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                for (final slot in mandatory) _buildSlot(context, slot),
                for (final extra in _extraDocTypes)
                    _buildSlot(
                      context,
                      _DocSlot(
                        docType: extra,
                        label: extra == 'CERTIFICATE'
                            ? s.tr('verify.certificateLabel')
                            : s.tr('verify.slotOther'),
                      ),
                    ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _extraDocTypes.length < 2 ? _addExtraSlot : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(s.tr('verify.addMore')),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_outlined),
                  label: Text(_submitting
                      ? s.tr('verify.submitting')
                      : s.tr('verify.submit')),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pushNamedAndRemoveUntil(
                            PublicHomePage.routeName,
                            (route) => false,
                          ),
                  child: Text(s.tr('auth.verificationLater')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlot(BuildContext context, _DocSlot slot) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final file = _picked[slot.docType];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              file != null ? Icons.description_outlined : Icons.attach_file,
              color: file != null ? Colors.green : theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slot.label,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (slot.hint != null)
                    Text(
                      slot.hint!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (file != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        file.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.green),
                      ),
                    ),
                ],
              ),
            ),
            if (file != null)
              IconButton(
                tooltip: s.tr('verify.remove'),
                onPressed: () => setState(() => _picked.remove(slot.docType)),
                icon: const Icon(Icons.close, size: 18),
              ),
            TextButton.icon(
              onPressed: () => _pick(slot.docType, slot.label),
              icon: const Icon(Icons.folder_open, size: 18),
              label: Text(file != null
                  ? s.tr('verify.selectFile')
                  : s.tr('verify.selectFile')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(String docType, String label) async {
    final s = AppLocalizations.of(context);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      );
      if (files.isNotEmpty && mounted) {
        setState(() => _picked[docType] = files.first);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.tr('verify.uploadError'))),
        );
      }
    }
  }

  void _addExtraSlot() {
    final n = _extraDocTypes.length;
    final docType = n == 0 ? 'OTHER' : 'CERTIFICATE';
    setState(() => _extraDocTypes.add(docType));
  }

  Future<void> _submit() async {
    final s = AppLocalizations.of(context);
    final controller = _controller;
    final access = controller.accessToken;
    if (access == null || access.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.tr('auth.sessionExpired'))),
      );
      return;
    }
    final mandatory = _isFacility
        ? const ['FACILITY_REGISTRATION', 'NATIONAL_ID']
        : ['CERTIFICATE', 'NATIONAL_ID'];
    final missing = mandatory.where((d) => _picked[d] == null).toList();
    var needIdentity = false;
    if (_isFacility) {
      needIdentity =
          _nameController.text.trim().isEmpty || _facilityType == null;
    }
    if (missing.isNotEmpty || needIdentity) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.tr('verify.missingDocs'))),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      var ok = true;
      final uploaded = <VerificationUploadedDoc>[];
      for (final entry in _picked.entries) {
        final docType = entry.key;
        final file = entry.value;
        try {
          final bytes = await file.readAsBytes();
          uploaded.add(await controller.repository.uploadVerificationDocument(
            access: access,
            docType: docType,
            fileBytes: bytes,
            filePath: file.path,
            fileName: file.name,
          ));
        } catch (_) {
          ok = false;
          break;
        }
      }
      if (!ok) {
        throw Exception('upload');
      }
      await controller.repository.submitVerificationDocuments(
        access: access,
        isFacility: _isFacility,
        professionalType: _effectiveRole,
        facilityProfile: _isFacility
            ? {
                'facility_type': _facilityType!,
                'name': _nameController.text.trim(),
                'city': _cityController.text.trim(),
                if (_regNoController.text.trim().isNotEmpty)
                  'registration_number': _regNoController.text.trim(),
              }
            : const {},
        documents: uploaded,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.verified_outlined, color: Colors.green, size: 40),
          title: Text(s.tr('verify.doneTitle')),
          content: Text(s.tr('verify.doneBody')),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(s.tr('verify.reviewStatus')),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        _isFacility
            ? OrganizationVerificationPage.routeName
            : DoctorVerificationPage.routeName,
        (route) => false,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.tr('verify.submitFailed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _DocSlot {
  const _DocSlot({required this.docType, required this.label, this.hint});

  final String docType;
  final String label;
  final String? hint;
}