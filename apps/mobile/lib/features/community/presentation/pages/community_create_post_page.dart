import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../data/community_repository.dart';

/// Create-post screen (approved COM-003; FR-COM-001).
///
/// Restates the data boundary: no private medical information belongs in a
/// community post. The backend sanitizes HTML and rate-limits creation
/// (30/min, §29).
class CommunityCreatePostView extends StatefulWidget {
  const CommunityCreatePostView({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final CommunityRepository repository;

  @override
  State<CommunityCreatePostView> createState() => _CommunityCreatePostViewState();
}

class _CommunityCreatePostViewState extends State<CommunityCreatePostView> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  String _category = communityCategories.first;
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.postSaveFailed)),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.repository.createPost(
        access: widget.accessToken,
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        category: _category,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.postPublished)),
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.postSaveFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.createPost)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(AppStrings.postShareConsent),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: AppStrings.postTitle,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentController,
              maxLines: 6,
              maxLength: 20000,
              decoration: const InputDecoration(
                labelText: AppStrings.postContent,
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: AppStrings.postCategory,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final category in communityCategories)
                  DropdownMenuItem(value: category, child: Text(category)),
              ],
              onChanged: (value) => setState(() => _category = value ?? _category),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(AppStrings.publishPost),
            ),
          ],
        ),
      ),
    );
  }
}
