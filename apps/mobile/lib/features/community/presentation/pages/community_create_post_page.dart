import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../data/community_repository.dart';

/// Create-post screen (approved COM-003; FR-COM-001).
///
/// Categories come from `GET /api/community/categories/`. A local fallback keeps
/// the form usable if that optional read degrades; publishing itself always goes
/// through the server, which re-validates the category. The screen restates the
/// data boundary: no private medical information belongs in a community post.
class CommunityCreatePostView extends StatefulWidget {
  const CommunityCreatePostView({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final CommunityRepository repository;

  @override
  State<CommunityCreatePostView> createState() =>
      _CommunityCreatePostViewState();
}

class _CommunityCreatePostViewState extends State<CommunityCreatePostView> {
  static const _fallback = ForumCategory(
    uid: '',
    slug: 'community-voices',
    name: 'Community Voices',
    legacyCode: 'GENERAL',
  );

  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  List<ForumCategory> _categories = const [_fallback];
  String _categorySlug = _fallback.slug;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await widget.repository.listCategories(
        access: widget.accessToken,
      );
      if (!mounted || categories.isEmpty) return;
      setState(() {
        _categories = categories;
        if (!categories.any((c) => c.slug == _categorySlug)) {
          _categorySlug = categories.first.slug;
        }
      });
    } catch (_) {
      // Keep the fallback category when the optional lookup fails.
    }
  }

  Future<void> _submit() async {
    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStrings.postSaveFailed)));
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.repository.createPost(
        access: widget.accessToken,
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        categorySlug: _categorySlug,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStrings.postPublished)));
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStrings.postSaveFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.createPost)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(AppStrings.postShareConsent),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: AppStrings.postTitle,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentController,
              maxLines: 6,
              maxLength: 20000,
              decoration: InputDecoration(
                labelText: AppStrings.postContent,
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _categorySlug,
              decoration: InputDecoration(
                labelText: AppStrings.postCategory,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final category in _categories)
                  DropdownMenuItem(
                    value: category.slug,
                    child: Text(category.name),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _categorySlug = value ?? _categorySlug),
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
                  : Text(AppStrings.publishPost),
            ),
          ],
        ),
      ),
    );
  }
}
