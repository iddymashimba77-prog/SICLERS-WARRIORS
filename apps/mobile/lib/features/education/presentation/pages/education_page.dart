import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/education_repository.dart';
import 'education_bookmarks_page.dart';
import 'education_detail_page.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../shared/widgets/signed_out_gate.dart';

/// Education library (approved EDU-001 categories / EDU-002 library + search;
/// FR-EDU-001..004). Read-only published content from a verified care team —
/// medical advice disclaimer is surfaced on the detail screen.
class EducationPage extends StatelessWidget {
  const EducationPage({super.key, this.authController, this.repository});

  static const String routeName = '/education';

  final AuthController? authController;
  final EducationRepository? repository;

  @override
  Widget build(BuildContext context) {
    final token = (authController ?? SessionScope.controllerOf(context))
        .accessToken;
    if (token == null) {
      return const SignedOutGate();
    }
    return EducationLibraryView(
      accessToken: token,
      repository:
          repository ?? EducationRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class EducationLibraryView extends StatefulWidget {
  const EducationLibraryView({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final EducationRepository repository;

  @override
  State<EducationLibraryView> createState() => _EducationLibraryViewState();
}

class _EducationLibraryViewState extends State<EducationLibraryView> {
  final _searchController = TextEditingController();

  List<EducationCategory> _categories = const <EducationCategory>[];
  List<EducationalContent>? _content;
  int _loadedCategories = 0;
  bool _loading = true;
  Object? _error;
  String? _categoryCode;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_loadedCategories == 0) {
        _categories = await widget.repository
            .listCategories(access: widget.accessToken);
      }
      _loadedCategories = 1;
      final content = await widget.repository.listContent(
        access: widget.accessToken,
        query: _query,
        category: _categoryCode,
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

  void _selectCategory(String? code) {
    setState(() => _categoryCode = code);
    _load();
  }

  void _search(String value) {
    setState(() => _query = value);
    _load();
  }

  Future<void> _openDetail(EducationalContent item) async {
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
  }

  Future<void> _openBookmarks() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EducationBookmarksView(
          accessToken: widget.accessToken,
          repository: widget.repository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.education),
        actions: [
          IconButton(
            tooltip: AppStrings.bookmarks,
            icon: const Icon(Icons.bookmark_outline),
            onPressed: _openBookmarks,
          ),
        ],
      ),
      body: Column(
        children: [
          _SearchBar(
            controller: _searchController,
            onSubmitted: _search,
          ),
          _CategoryBar(
            categories: _categories,
            selected: _categoryCode,
            onSelected: _selectCategory,
          ),
          Expanded(child: _buildBody()),
        ],
      ),
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
    final content = _content ?? const <EducationalContent>[];
    if (content.isEmpty) {
      return EmptyStateView(
        message: AppStrings.noEducationContent,
        icon: Icons.auto_stories_outlined,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: content.length,
        itemBuilder: (_, i) => _ArticleCard(
          item: content[i],
          bookmarked: widget.repository.isBookmarked(content[i].uid),
          onTap: () => _openDetail(content[i]),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: AppStrings.searchEducation,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            tooltip: AppStrings.searchEducation,
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => onSubmitted(controller.text),
          ),
          border: OutlineInputBorder(
            borderRadius: AppShapes.tile,
          ),
          isDense: true,
        ),
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<EducationCategory> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(AppStrings.allCategories),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(category.name),
                selected: selected == category.code,
                onSelected: (_) => onSelected(category.code),
              ),
            ),
        ],
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({
    required this.item,
    required this.onTap,
    this.bookmarked = false,
  });

  final EducationalContent item;
  final VoidCallback onTap;
  final bool bookmarked;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppShapes.tile,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.coverUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: AppShapes.small,
                  child: Image.network(
                    item.coverUrl,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Icon(
                    Icons.school_outlined,
                    size: 16,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.category.name,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.secondary),
                    ),
                  ),
                  if (bookmarked)
                    const Icon(
                      Icons.bookmark,
                      size: 16,
                      color: AppColors.secondary,
                    ),
                ],
              ),
              if (item.title.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item.title, style: Theme.of(context).textTheme.titleMedium),
              ],
              const SizedBox(height: 6),
              Text(
                item.body.replaceAll(RegExp(r'<[^>]+>'), ''),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                '${AppStrings.publishedOn} ${item.author.displayName}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}