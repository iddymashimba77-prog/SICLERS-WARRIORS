import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../data/education_repository.dart';

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
        title: const Text(AppStrings.education),
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
      return const EmptyStateView(message: AppStrings.noEducationContent);
    }
    final plainBody = content.body.replaceAll(RegExp(r'<[^>]+>'), '');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: AppColors.secondary.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.secondary),
                const SizedBox(width: 10),
                const Expanded(child: Text(AppStrings.educationNotMedicalAdvice)),
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
        const SizedBox(height: 16),
        Text(plainBody, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}