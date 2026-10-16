/// Reviewer-side verification-document surface (C5/C6).
///
/// Lists the attachments an applicant submitted and opens them on demand. The
/// file is fetched as authenticated bytes from the audited
/// `GET /admin/verification-documents/{id}/` endpoint — never a public URL — so
/// images preview in-app and non-image documents are handed to the device's own
/// viewer.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import 'admin_widgets.dart';

/// Human label for a verification `doc_type` (falls back to the raw code).
String documentTypeLabel(String code) {
  switch (code) {
    case 'CERTIFICATE':
      return tr('admin.doctype.certificate');
    case 'NATIONAL_ID':
      return tr('admin.doctype.nationalId');
    case 'FACILITY_REGISTRATION':
      return tr('admin.doctype.facilityRegistration');
    case 'LICENSE':
      return tr('admin.doctype.license');
    default:
      return code.isEmpty ? tr('admin.doctype.document') : code;
  }
}

/// The "Submitted documents" block for one doctor/facility review card.
///
/// Renders nothing when the applicant has attached no documents, so a queue the
/// reviewer cannot act on stays compact.
class SubmittedDocumentsSection extends StatefulWidget {
  const SubmittedDocumentsSection({
    super.key,
    required this.documents,
    required this.repository,
    required this.accessToken,
  });

  final List<AdminVerificationDocument> documents;
  final AdminRepository repository;
  final String accessToken;

  @override
  State<SubmittedDocumentsSection> createState() =>
      _SubmittedDocumentsSectionState();
}

class _SubmittedDocumentsSectionState extends State<SubmittedDocumentsSection> {
  int? _opening;

  Future<void> _open(AdminVerificationDocument doc) async {
    setState(() => _opening = doc.id);
    try {
      final result = await widget.repository.fetchVerificationDocument(
        access: widget.accessToken,
        id: doc.id,
      );
      if (!mounted) return;
      await _showDocument(context, doc, result);
    } on Exception {
      if (mounted) showAdminMessage(context, tr('admin.couldNotOpenDocument'));
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<void> _showDocument(
    BuildContext context,
    AdminVerificationDocument doc,
    AdminDocumentBytes bytes,
  ) async {
    if (bytes.contentType.startsWith('image/')) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => _DocumentImagePage(
            title: documentTypeLabel(doc.docType),
            bytes: bytes.bytes,
          ),
        ),
      );
      return;
    }
    final opened = await _openExternally(doc, bytes);
    if (!opened && context.mounted) {
      showAdminMessage(context, tr('admin.noAppToOpen'));
    }
  }

  Future<bool> _openExternally(
    AdminVerificationDocument doc,
    AdminDocumentBytes bytes,
  ) async {
    try {
      final dir = await Directory.systemTemp.createTemp('sw_verification');
      final name = doc.fileName.isNotEmpty ? doc.fileName : 'document';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes.bytes, flush: true);
      return await launchUrl(Uri.file(file.path),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = widget.documents;
    if (docs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Text(
          tr('admin.noVerifDocs'),
          style: const TextStyle(fontSize: 12),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('admin.submittedDocuments'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final doc in docs)
                OutlinedButton.icon(
                  onPressed: _opening == null ? () => _open(doc) : null,
                  icon: _opening == doc.id
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.description_outlined, size: 16),
                  label: Text(
                    '${documentTypeLabel(doc.docType)} · ${tr('admin.view')}',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DocumentImagePage extends StatelessWidget {
  const _DocumentImagePage({required this.title, required this.bytes});

  final String title;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
