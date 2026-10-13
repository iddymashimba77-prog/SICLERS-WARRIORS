import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../data/content_repository.dart';
import '../../domain/content_models.dart';
import '../widgets/content_widgets.dart';
import 'news_detail_page.dart';
import '../../../../core/theme/app_shapes.dart';

/// Public news archive: category filter + paginated "load more" list.
///
/// Reachable directly from the public home header/sections. Reads the same
/// unauthenticated `/api/content/news/` surface as the home page.
class NewsListPage extends StatefulWidget {
  const NewsListPage({super.key, ContentRepository? repository})
      : _repository = repository;

  static const String routeName = '/news';

  final ContentRepository? _repository;

  @override
  State<NewsListPage> createState() => _NewsListPageState();
}

class _NewsListPageState extends State<NewsListPage> {
  late final ContentRepository _content =
      widget._repository ?? ContentRepository();

  List<PublicNewsArticle> _items = [];
  List<NewsCategory> _categories = [];
  String _category = '';
  int _page = 1;
  bool _hasNext = false;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final categories = await _content.listCategories();
      final page = await _content.listNews(
        page: 1,
        category: _category.isEmpty ? null : _category,
      );
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _items = page.items;
        _page = 1;
        _hasNext = page.hasNext;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _loadMore() async {
    try {
      final page = await _content.listNews(
        page: _page + 1,
        category: _category.isEmpty ? null : _category,
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _page += 1;
        _hasNext = page.hasNext;
      });
    } catch (_) {/* stay on current page; button remains for retry */}
  }

  void _openArticle(PublicNewsArticle article) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NewsDetailPage(uid: article.uid, intro: article),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          AppStrings.appName,
          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy),
        ),
      ),
      body: _loading
          ? const SkeletonListView(rows: 4)
          : _error
              ? ErrorRetryView(
                  message: 'We couldn\'t load the news. Check your connection.',
                  onRetry: _load,
                )
              : _body(context),
    );
  }

  Widget _body(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0,
          ),
          child: Text(
            'Latest News & Updates',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        if (_categories.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0,
              ),
              itemCount: _categories.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final selected = index == 0 && _category.isEmpty;
                final label = index == 0 ? 'All' : _categories[index - 1].label;
                return ChoiceChip(
                  label: Text(label),
                  selected: index == 0
                      ? _category.isEmpty
                      : _category == _categories[index - 1].code,
                  onSelected: (_) {
                    if (selected) return;
                    setState(() {
                      _category = index == 0 ? '' : _categories[index - 1].code;
                    });
                    _load();
                  },
                );
              },
            ),
          ),
        Expanded(
          child: _items.isEmpty
              ? const EmptyStateView(
                  icon: Icons.article_outlined,
                  title: 'Nothing here yet',
                  message: 'New announcements will appear here.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: _items.length + (_hasNext ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, index) {
                    if (index == _items.length) {
                      return SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _loadMore,
                          icon: const Icon(Icons.expand_more),
                          label: const Text('Load more updates'),
                        ),
                      );
                    }
                    return _NewsCard(
                      article: _items[index],
                      onTap: () => _openArticle(_items[index]),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.article, required this.onTap});

  final PublicNewsArticle article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: AppShapes.large,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PublicNewsCover(
              url: article.coverUrl,
              alt: article.coverAlt,
              height: 150,
              borderRadius: 18,
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (article.categoryLabel.isNotEmpty) ...[
                        PublicNewsCategoryChip(label: article.categoryLabel),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      if (article.featured)
                        const Icon(Icons.star,
                            size: 16, color: AppColors.warning),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    article.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                  ),
                  if (article.excerpt.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      article.excerpt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  PublicNewsMetaRow(
                    publishedAt: article.publishedAt,
                    author: article.authorName,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}