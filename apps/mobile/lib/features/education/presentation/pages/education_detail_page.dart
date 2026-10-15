import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../data/education_repository.dart';
import '../../../../core/theme/app_shapes.dart';

/// Article detail (approved EDU-003; FR-EDU-001/002/004).
///
/// Published content only. The banner restates that this is educational, not
/// personalised medical advice. Bookmarking is a local, session-only toggle
/// (EDU-005) — nothing leaves the device.
class EducationDetailView extends StatefulWidget {
  const EducationDetailView({
    super.key,
    required this.accessToken,
    required this.repository,
    required this.contentUid,
  });

  final String accessToken;
  final EducationRepository repository;
  final String contentUid;

  @override
  State<EducationDetailView> createState() => _EducationDetailViewState();
}

class _EducationDetailViewState extends State<EducationDetailView> {
  EducationalContent? _content;
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
      final content = await widget.repository.getContent(
        access: widget.accessToken,
        uid: widget.contentUid,
      );
      if (!mounted) return;
      setState(() {
        _content = content;
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

  void _toggleBookmark() {
    setState(() => widget.repository.toggleBookmark(widget.contentUid));
  }

  @override
  Widget build(BuildContext context) {
    final bookmarked = widget.repository.isBookmarked(widget.contentUid);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.education),
        actions: [
          IconButton(
            tooltip: bookmarked ? AppStrings.bookmarkedSaved : AppStrings.bookmarks,
            icon: Icon(
              bookmarked ? Icons.bookmark : Icons.bookmark_border,
            ),
            onPressed: _toggleBookmark,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return ErrorRetryView(
        message: AppStrings.educationLoadFailed,
        onRetry: _load,
      );
    }
    final content = _content;
    if (content == null) {
      return EmptyStateView(message: AppStrings.noEducationContent);
    }
    final plainBody = content.body.replaceAll(RegExp(r'<[^>]+>'), '');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (content.coverUrl.isNotEmpty) ...[
          ClipRRect(
            borderRadius: AppShapes.tile,
            child: Image.network(
              content.coverUrl,
              height: 180,
              width: double.infinity,
              fit: BoxFit.contain,
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Card(
          color: AppColors.secondary.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.secondary),
                const SizedBox(width: 10),
                Expanded(child: Text(AppStrings.educationNotMedicalAdvice)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(content.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              avatar: const Icon(Icons.school_outlined, size: 16),
              label: Text(content.category.name),
            ),
            Chip(
              avatar: const Icon(Icons.person_outline, size: 16),
              label: Text(content.author.displayName),
            ),
            if (content.publishedAt != null)
              Chip(
                avatar: const Icon(Icons.calendar_today_outlined, size: 14),
                label: Text(
                  content.publishedAt!.substring(0, 10),
                ),
              ),
          ],
        ),
        if (content.hasDocument) ...[
          const SizedBox(height: 20),
          _HandoutCard(content: content),
        ],
        const SizedBox(height: 16),
        Text(plainBody, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

/// Downloadable handout attached to the article (FR-EDU-005).
///
/// Opening the URL in the system viewer rather than downloading it inside the
/// app keeps a file the patient did not choose off our storage, and lets them
/// use whichever PDF reader they already trust.
class _HandoutCard extends StatefulWidget {
  const _HandoutCard({required this.content});

  final EducationalContent content;

  @override
  State<_HandoutCard> createState() => _HandoutCardState();
}

class _HandoutCardState extends State<_HandoutCard> {
  Future<void> _open() async {
    final s = AppLocalizations.of(context);
    final url = widget.content.documentUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _notify(s.tr('edu.document.badLink'));
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    // The launch crosses an async gap, so re-check before touching the tree.
    if (!ok && mounted) _notify(s.tr('edu.document.noApp'));
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppLocalizations.of(context);
    final content = widget.content;
    final label =
        content.documentName.isEmpty ? s.tr('edu.document.download') : content.documentName;
    final size = content.readableDocumentSize;
    return Card(
      child: InkWell(
        onTap: _open,
        borderRadius: AppShapes.tile,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.attachment_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.tr('edu.document.download'),
                      style: theme.textTheme.labelSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      size.isEmpty ? label : '$label · $size',
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}