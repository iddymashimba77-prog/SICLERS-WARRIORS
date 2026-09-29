import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../data/content_repository.dart';
import '../../domain/content_models.dart';
import '../widgets/content_widgets.dart';

/// Single public article: full body with cover header, category chip and meta.
///
/// Accepts an optional [intro] summary so the list page can render instantly
/// while the full body streams in.
class NewsDetailPage extends StatefulWidget {
  const NewsDetailPage({super.key, required this.uid, this.intro});

  static const String routePrefix = '/news/detail';

  final String uid;
  final PublicNewsArticle? intro;

  @override
  State<NewsDetailPage> createState() => _NewsDetailPageState();
}

class _NewsDetailPageState extends State<NewsDetailPage> {
  late final ContentRepository _content = ContentRepository();

  PublicNewsDetail? _detail;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _detail == null;
      _error = false;
    });
    try {
      final detail = await _content.getNews(widget.uid);
      if (!mounted) return;
      setState(() {
        _detail = detail;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Article'),
      ),
      body: _loading
          ? const SkeletonListView(rows: 4)
          : _error
              ? ErrorRetryView(
                  message: 'We couldn\'t open this article. Check your connection.',
                  onRetry: _load,
                )
              : _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final detail = _detail;
    final summary = detail ?? widget.intro;
    final theme = Theme.of(context);
    if (summary == null) {
      return ErrorRetryView(
        message: 'This article is no longer available.',
        onRetry: _loadOrPop,
      );
    }

    final hasBody = detail != null && detail.body.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (summary.coverUrl.isNotEmpty) ...[
          PublicNewsCover(
            url: summary.coverUrl,
            alt: summary.coverAlt,
            height: 210,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (summary.categoryLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: PublicNewsCategoryChip(label: summary.categoryLabel),
          ),
        Text(
          summary.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        PublicNewsMetaRow(
          publishedAt: summary.publishedAt,
          author: summary.authorName,
        ),
        if (summary.excerpt.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            summary.excerpt,
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
              fontStyle: FontStyle.italic,
              height: 1.45,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        const Divider(color: AppColors.border),
        const SizedBox(height: AppSpacing.md),
        Text(
          hasBody ? detail.body : summary.excerpt,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: AppColors.textPrimary,
            height: 1.65,
          ),
        ),
        if (hasBody) ...[
          const SizedBox(height: AppSpacing.xl),
          const Divider(color: AppColors.border),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.favorite, color: AppColors.emergency, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Thank you for reading. Every warrior\'s story helps raise awareness.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  void _loadOrPop() {
    if (_detail == null && widget.intro == null) {
      Navigator.of(context).maybePop();
    } else {
      _load();
    }
  }
}