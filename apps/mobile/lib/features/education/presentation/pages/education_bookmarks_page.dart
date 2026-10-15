import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../data/education_repository.dart';
import 'education_detail_page.dart';

/// Saved articles (approved EDU-005).
///
/// Bookmarks are stored on this device for this session only — they are never
/// sent to the server and are lost when the app restarts. Items are fetched
/// on demand so the list always reflects the latest approved content.
class EducationBookmarksView extends StatefulWidget {
  const EducationBookmarksView({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final EducationRepository repository;

  @override
  State<EducationBookmarksView> createState() => _EducationBookmarksViewState();
}

class _EducationBookmarksViewState extends State<EducationBookmarksView> {
  List<EducationalContent>? _items;
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
      final uids = widget.repository.bookmarkedUids;
      // Stage 4.18: fetch all bookmarked articles in parallel instead of one
      // serial request per bookmark. Each request is isolated so a single
      // deleted/404 article is skipped without failing the whole list.
      final results = await Future.wait<EducationalContent?>(
        uids.map((uid) async {
          try {
            return await widget.repository.getContent(
              access: widget.accessToken,
              uid: uid,
            );
          } catch (_) {
            return null;
          }
        }),
      );
      final items = results.whereType<EducationalContent>().toList(growable: false);
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

  Future<void> _open(EducationalContent item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EducationDetailView(
          accessToken: widget.accessToken,
          repository: widget.repository,
          contentUid: item.uid,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {});
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.bookmarks)),
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
    final items = _items ?? const <EducationalContent>[];
    if (items.isEmpty) {
      return EmptyStateView(
        message: '${AppStrings.noBookmarks}\n${AppStrings.noBookmarksHint}',
        icon: Icons.bookmark_border,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final item = items[i];
          return ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(item.category.name),
            onTap: () => _open(item),
          );
        },
      ),
    );
  }
}